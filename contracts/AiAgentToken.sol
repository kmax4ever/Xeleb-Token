// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
contract AiAgentToken is Ownable {
    using Math for uint256;
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 public totalSupply;

    mapping(address => bool) private _admins;
    uint32 private holders;

    // Token distribution pools
    uint256 public constant BONDING_CURVE_PERCENT = 70; // 75% of total supply
    uint256 public constant STAKING_REWARD_PERCENT = 5; // 5% of total supply ,6% from fee
    uint256 public constant LIQUIDITY_PERCENT = 20; // 20% of total supply
    uint256 public constant CREATOR_PERCENT = 5; // 5% of total supply

    uint256 public constant BONDING_UNLOCK_PERCENT = 10;
    uint256 public constant BONDING_VESTING_PERCENT = 90;
    uint256 public constant BONDING_VESTING_TIMES = 270 days;

    uint256 public constant CREATOR_VESTING_TIMES = 720 days; //
    uint256 public constant CREATOR_UNLOCK_PERCENT = 25;
    uint256 public constant CREATOR_VESTING_PERCENT = 75;

    //TEAM
    uint256 public constant CLIFF_PERIOD = 0; // 0 cliff
    // Fee structure
    uint256 public constant MIN_FEE = 10;
    uint256 public constant BASE_BURN_RATE = 20; // 0.2%
    uint256 public constant FEE_DENOMINATOR = 10000;

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 startTime;
        uint256 cliffEnd;
        uint256 endTime;
        uint256 lastClaimTime;
        uint256 releasedAmount;
        bool revoked;
    }

    struct StakingPosition {
        uint256 amount;
        uint256 startTime;
        uint256 lockDuration;
        uint256 lastRewardTime;
        uint256 rewardRate;
    }

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => VestingSchedule) public vestingSchedules;
    mapping(address => uint256) public lastSellTime;
    mapping(address => uint256) public dailySellAmount;

    // Pool wallet addresses
    address public bondingWallet;
    address public liquidityWallet;
    address public stakingWallet;
    address public creatorWallet;

    event TokensVested(address indexed account, uint256 amount);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event VestingTokensClaimed(address indexed account, uint256 amount);
    event VestingCompleted(address indexed account, uint256 totalAmount);

    modifier onlyAdmin() {
        require(_admins[msg.sender], "caller is not an admin");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address _adminWallet,
        address _stakingWallet,
        address _creatorWallet,
        uint256 _totalSupply
    ) Ownable(_adminWallet) {
        require(_stakingWallet != address(0), "Invalid staking wallet");
        require(_creatorWallet != address(0), "Invalid creatorWallet wallet");
        _admins[_adminWallet] = true;
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;

        // Set wallet addresses
        stakingWallet = _stakingWallet;
        creatorWallet = _creatorWallet;
        // Initialize config
        totalSupply = _totalSupply;

        uint256 stakingAmount = (_totalSupply * STAKING_REWARD_PERCENT) / 100;
        _mint(stakingWallet, stakingAmount);
    }

    function createVestingScheduleForCreator(
        address account,
        uint256 amount
    ) public onlyAdmin {
        _createVestingSchedule(
            account,
            amount,
            CLIFF_PERIOD,
            CREATOR_VESTING_TIMES,
            CREATOR_UNLOCK_PERCENT,
            CREATOR_VESTING_PERCENT
        );
    }

    function createVestingScheduleForBuyer(
        address account,
        uint256 amount
    ) public onlyAdmin {
        _createVestingSchedule(
            account,
            amount,
            CLIFF_PERIOD,
            BONDING_VESTING_TIMES,
            BONDING_UNLOCK_PERCENT,
            BONDING_VESTING_PERCENT
        );
    }

    function _createVestingSchedule(
        address account,
        uint256 amount,
        uint256 period,
        uint256 duration,
        uint256 unlockPercent,
        uint256 vestingPercent
    ) internal {
        require(account != address(0), "Invalid account address");
        require(amount > 0, "Amount must be greater than 0");
        require(unlockPercent + vestingPercent <= 100, "Invalid percentages");

        uint256 unlockAmount = (amount * unlockPercent) / 100;
        uint256 vestingAmount = (amount * vestingPercent) / 100;
        _mint(account, unlockAmount);

        VestingSchedule storage existingSchedule = vestingSchedules[account];
        if (existingSchedule.totalAmount > 0) {
            require(!existingSchedule.revoked, "Existing schedule is revoked");

            uint256 remainingVested = existingSchedule.totalAmount -
                existingSchedule.releasedAmount;

            vestingSchedules[account] = VestingSchedule({
                totalAmount: remainingVested + vestingAmount,
                startTime: existingSchedule.startTime,
                cliffEnd: existingSchedule.cliffEnd,
                endTime: existingSchedule.endTime,
                lastClaimTime: existingSchedule.lastClaimTime,
                releasedAmount: existingSchedule.releasedAmount,
                revoked: false
            });
        } else {
            uint256 start = block.timestamp;
            uint256 cliff = start + period;
            uint256 end = start + duration;
            vestingSchedules[account] = VestingSchedule({
                totalAmount: vestingAmount,
                startTime: start,
                cliffEnd: cliff,
                endTime: end,
                lastClaimTime: start,
                releasedAmount: 0,
                revoked: false
            });
        }

        emit TokensVested(account, vestingAmount);
    }

    function _calculateClaimableAmount(
        VestingSchedule memory schedule
    ) internal view returns (uint256) {
        if (block.timestamp < schedule.cliffEnd) return 0;

        if (block.timestamp >= schedule.endTime) {
            return schedule.totalAmount - schedule.releasedAmount;
        }
        uint256 timeFromStart = block.timestamp - schedule.startTime;
        uint256 vestingDuration = schedule.endTime - schedule.startTime;

        uint256 vestedAmount = (schedule.totalAmount * timeFromStart) /
            vestingDuration;
        if (vestedAmount > schedule.totalAmount) {
            vestedAmount = schedule.totalAmount;
        }
        uint256 remainingClaimable = 0;
        if (vestedAmount > schedule.releasedAmount) {
            remainingClaimable = vestedAmount - schedule.releasedAmount;
        }
        return remainingClaimable;
    }

    function _claimVestedTokens(
        address account,
        uint256 amount
    ) internal returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[account];

        require(!schedule.revoked, "Vesting revoked");
        require(block.timestamp >= schedule.cliffEnd, "Cliff period not ended");

        uint256 claimableAmount = _calculateClaimableAmount(schedule);
        require(claimableAmount >= amount, "Insufficient vested tokens");
        schedule.releasedAmount += amount;
        _mint(account, amount);
        schedule.lastClaimTime = block.timestamp;

        if (schedule.releasedAmount >= schedule.totalAmount) {
            delete vestingSchedules[account];
            emit VestingCompleted(account, schedule.totalAmount);
        }
        emit VestingTokensClaimed(account, amount);
        return amount;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        address sender = msg.sender;
        require(sender != to, "Not allow self transfer!");
        require(balanceOf(sender) >= amount, "Not enough amount!");
        _transfer(sender, to, amount);
        return true;
    }

    function name() public view returns (string memory) {
        return _name;
    }
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account) public view returns (uint256) {
        uint256 actualBalance = _balances[account];

        VestingSchedule memory schedule = vestingSchedules[account];
        if (
            schedule.totalAmount > 0 &&
            !schedule.revoked &&
            block.timestamp >= schedule.cliffEnd
        ) {
            uint256 claimableAmount = _calculateClaimableAmount(schedule);
            return actualBalance + claimableAmount;
        }

        return actualBalance;
    }
    function setAdmin(address account, bool _isAdmin) public onlyOwner {
        _admins[account] = _isAdmin;
    }

    function isAdmin(address account) public view returns (bool) {
        return _admins[account];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function allowance(address from, address to) public view returns (uint256) {
        return _allowances[from][to];
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
    function mint(address to, uint256 amount) public onlyAdmin {
        _mint(to, amount);
    }
    function _mint(address account, uint256 amount) private {
        require(account != address(0), "ERC20: mint to the zero address");
        uint256 balanceBeforeMint = _balances[account];
        unchecked {
            _balances[account] += amount;
        }
        if (balanceBeforeMint == 0 && _balances[account] > 0) {
            holders++;
        }

        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) private {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 actualBalance = _balances[account];
        uint256 totalBalance = balanceOf(account);
        require(totalBalance >= amount, "ERC20: burn amount exceeds balance");
        if (actualBalance < amount) {
            uint256 needFromVesting = amount - actualBalance;
            _claimVestedTokens(account, needFromVesting);
            actualBalance = _balances[account];
        }

        unchecked {
            _balances[account] = actualBalance - amount;
            if (
                _balances[account] == 0 &&
                vestingSchedules[account].releasedAmount ==
                vestingSchedules[account].totalAmount
            ) {
                holders--;
            }
        }
        emit Transfer(account, address(0), amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 actualBalance = _balances[from];
        uint256 totalBalance = balanceOf(from);
        require(
            totalBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        if (actualBalance < amount) {
            uint256 needFromVesting = amount - actualBalance;
            _claimVestedTokens(from, needFromVesting);
            actualBalance = _balances[from];
        }
        uint256 balanceOfToBeforeTransfer = _balances[to];

        unchecked {
            _balances[from] = actualBalance - amount;
            _balances[to] += amount;

            if (
                _balances[from] == 0 &&
                vestingSchedules[from].releasedAmount ==
                vestingSchedules[from].totalAmount
            ) {
                holders--;
            }
            if (balanceOfToBeforeTransfer == 0 && _balances[to] > 0) {
                holders++;
            }
        }

        emit Transfer(from, to, amount);
    }

    function getDetailsAccount(
        address account
    )
        public
        view
        returns (
            uint256 actualBalance,
            uint256 vestedBalance,
            uint256 claimableAmount,
            uint256 totalBalance,
            uint256 vestingEndTime,
            uint256 releasedAmount
        )
    {
        actualBalance = _balances[account];
        vestedBalance = 0;
        claimableAmount = 0;
        vestingEndTime = 0;

        VestingSchedule memory schedule = vestingSchedules[account];
        if (
            schedule.totalAmount > 0 &&
            !schedule.revoked &&
            block.timestamp >= schedule.cliffEnd
        ) {
            vestedBalance = schedule.totalAmount;
            claimableAmount = _calculateClaimableAmount(schedule);
            vestingEndTime = schedule.endTime;
        }

        totalBalance = actualBalance + claimableAmount;
        releasedAmount = schedule.releasedAmount;
        return (
            actualBalance,
            vestedBalance,
            claimableAmount,
            totalBalance,
            vestingEndTime,
            releasedAmount
        );
    }

    function vestingDetails(
        address account
    ) public view returns (VestingSchedule memory schedule) {
        schedule = vestingSchedules[account];
    }

    function getHolderCount() public view returns (uint256) {
        return holders;
    }
}
