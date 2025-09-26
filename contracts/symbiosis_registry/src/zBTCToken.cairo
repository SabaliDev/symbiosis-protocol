#[starknet::contract]
mod ZBTCToken {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        name: felt252,
        symbol: felt252,
        decimals: u8,
        total_supply: u256,
        balances: LegacyMap::<ContractAddress, u256>,
        allowances: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        registry_contract: ContractAddress,
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        Mint: Mint,
        Burn: Burn,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        #[key]
        owner: ContractAddress,
        #[key]
        spender: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Mint {
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Burn {
        #[key]
        from: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        registry_contract: ContractAddress,
        owner: ContractAddress
    ) {
        self.name.write(name);
        self.symbol.write(symbol);
        self.decimals.write(decimals);
        self.total_supply.write(0);
        self.registry_contract.write(registry_contract);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl IERC20Impl of IERC20<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.decimals.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self.allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let caller = get_caller_address();
            let current_allowance = self.allowances.read((sender, caller));
            
            assert(current_allowance >= amount, 'Insufficient allowance');
            
            self.allowances.write((sender, caller), current_allowance - amount);
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self.allowances.write((caller, spender), amount);
            
            self.emit(Event::Approval(Approval {
                owner: caller,
                spender: spender,
                value: amount
            }));
            true
        }
    }

    #[abi(embed_v0)]
    impl ZBTCTokenImpl of IZBTCToken<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            // Only registry contract can mint
            assert(get_caller_address() == self.registry_contract.read(), 'Only registry can mint');
            
            let new_total_supply = self.total_supply.read() + amount;
            let new_balance = self.balances.read(to) + amount;
            
            self.total_supply.write(new_total_supply);
            self.balances.write(to, new_balance);
            
            self.emit(Event::Mint(Mint { to, amount }));
            self.emit(Event::Transfer(Transfer { 
                from: contract_address_const::<0>(), 
                to, 
                value: amount 
            }));
        }

        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            // Only registry contract can burn
            assert(get_caller_address() == self.registry_contract.read(), 'Only registry can burn');
            
            let current_balance = self.balances.read(from);
            assert(current_balance >= amount, 'Insufficient balance');
            
            let new_total_supply = self.total_supply.read() - amount;
            let new_balance = current_balance - amount;
            
            self.total_supply.write(new_total_supply);
            self.balances.write(from, new_balance);
            
            self.emit(Event::Burn(Burn { from, amount }));
            self.emit(Event::Transfer(Transfer { 
                from, 
                to: contract_address_const::<0>(), 
                value: amount 
            }));
        }

        fn get_registry_contract(self: @ContractState) -> ContractAddress {
            self.registry_contract.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _transfer(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
            assert(!sender.is_zero(), 'Transfer from zero address');
            assert(!recipient.is_zero(), 'Transfer to zero address');
            
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 'Insufficient balance');
            
            self.balances.write(sender, sender_balance - amount);
            let recipient_balance = self.balances.read(recipient);
            self.balances.write(recipient, recipient_balance + amount);
            
            self.emit(Event::Transfer(Transfer { from: sender, to: recipient, value: amount }));
        }
    }
}

#[starknet::interface]
trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
trait IZBTCToken<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
    fn get_registry_contract(self: @TContractState) -> ContractAddress;
}