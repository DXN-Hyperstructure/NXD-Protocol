pragma solidity >=0.8.0;

import "forge-std/console.sol";
import "./interfaces/INXDProtocol.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NXDStakingVault {
    using SafeERC20 for IERC20;

    error PoolAlreadyAdded();
    error InvalidAmount();
    error SendETHFail();
    error NoRequest();
    error Cooldown();
    error Underflow();

    error Locked();
    error WithdrawDisabled();

    event Add(address indexed token, uint256 indexed pid, uint256 allocPoint, bool withdrawable);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 _pid, uint256 value);
    event WithdrawRequested(address indexed user, uint256 amount, uint256 canWithdrawAfterTimestamp);

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many  tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
            //
            // We do some fancy math here. Basically, any point in time, the amount of ETHs
            // entitled to a user but is pending to be distributed is:
            //
            //   pending reward = (user.amount * pool.accEthPerShare) - user.rewardDebt
            //
            // Whenever a user deposits or withdraws  tokens to a pool. Here's what happens:
            //   1. The pool's `accEthPerShare` (and `lastRewardBlock`) gets updated.
            //   2. User receives the pending reward sent to his/her address.
            //   3. User's `amount` gets updated.
            //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of  token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. ETHs to distribute per block.
        uint256 accEthPerShare; // Accumulated ETHs per share, times 1e12. See below.
        bool withdrawable; // Is this pool withdrawable?
    }

    // Info of each pool.
    uint256 public numPools;
    mapping(uint256 => PoolInfo) public poolInfo;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // pid => owner => timestamp
    // mapping(uint256 => mapping(address => uint256)) public canWithdrawAfter;

    struct WithdrawalRequest {
        uint256 amount;
        uint256 canWithdrawAfterTimestamp;
    }

    // pid => owner => WithdrawalRequest
    mapping(uint256 => mapping(address => WithdrawalRequest)) public withdrawalRequests;

    uint256 public constant WITHDRAWAL_COOLDOWN = 1 days;

    //// pending rewards awaiting anyone to massUpdate
    uint256 public pendingRewards;

    uint256 public contractStartBlock;
    uint256 public epochCalculationStartBlock;
    uint256 public cumulativeRewardsSinceStart;
    uint256 public rewardsInThisEpoch;
    uint256 public epoch;
    mapping(uint256 => uint256) public epochRewards;

    // The NXD TOKEN!
    IERC20 public immutable nxd;
    INXDProtocol public immutable nxdProtocol;

    // keep track of latest known eth balance. used to determine new rewards
    uint256 public ourETHBalance;
    bool public locked;

    // Reentrancy lock
    modifier lock() {
        if (locked) {
            revert Locked();
        }
        locked = true;
        _;
        locked = false;
    }

    constructor(IERC20 _nxd) {
        nxd = _nxd;
        nxdProtocol = INXDProtocol(msg.sender);
        _add(100, _nxd, false, true);
    }

    // Add a new token pool. Can only be when contract is deployed.
    function _add(uint256 _allocPoint, IERC20 _token, bool _withUpdate, bool _withdrawable) internal {
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 length = numPools;
        for (uint256 pid = 0; pid < length; ++pid) {
            if (poolInfo[pid].token == _token) {
                revert PoolAlreadyAdded();
            }
        }

        totalAllocPoint = totalAllocPoint + _allocPoint;

        PoolInfo storage _poolInfo = poolInfo[numPools];

        _poolInfo.token = _token;
        _poolInfo.allocPoint = _allocPoint;
        _poolInfo.accEthPerShare = 0;
        _poolInfo.withdrawable = _withdrawable;

        numPools += 1;

        emit Add(address(_token), numPools - 1, _allocPoint, _withdrawable);
    }

    // View function to see pending ETHs on frontend.
    function pendingETH(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accEthPerShare = pool.accEthPerShare;

        return ((user.amount * accEthPerShare) / 1e12) - user.rewardDebt;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        console.log("Mass Updating Pools");
        uint256 length = numPools;
        uint256 allRewards;
        for (uint256 pid = 0; pid < length; ++pid) {
            console.log("massUpdatePools pid = ", pid);
            allRewards = allRewards + updatePool(pid);
        }

        pendingRewards = pendingRewards - allRewards;
    }

    function addPendingRewards() public {
        console.log("addPendingRewards address(this).balance =", address(this).balance);
        console.log("addPendingRewards ourETHBalance =", ourETHBalance);
        uint256 newRewards = address(this).balance - ourETHBalance;
        console.log("addPendingRewards newRewards =", newRewards);

        if (newRewards > 0) {
            ourETHBalance = address(this).balance; // If there is no change the balance didn't change
            pendingRewards = pendingRewards + newRewards;
            rewardsInThisEpoch = rewardsInThisEpoch + newRewards;
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) internal returns (uint256 ethReward) {
        console.log("updatePool _pid = ", _pid);
        PoolInfo storage pool = poolInfo[_pid];

        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (tokenSupply == 0) {
            // avoids division by 0 errors
            return 0;
        }
        console.log("updatePool tokenSupply = ", tokenSupply);
        ethReward = (pendingRewards * pool.allocPoint) // Multiplies pending rewards by allocation point of this pool and then total allocation
            // getting the percent of total pending rewards this pool should get
            / totalAllocPoint; // we can do this because pools are only mass updated
        console.log("updatePool ethReward = ", ethReward);
        pool.accEthPerShare += ((ethReward * 1e12) / tokenSupply);
        console.log("updatePool pool.accEthPerShare = ", pool.accEthPerShare);
    }

    // Deposit NXD tokens to NXDStakingVault for ETH allocation.
    function deposit(uint256 _pid, uint256 _amount) public lock {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        console.log("NXDStakingVault: user depositing %s tokens", _amount);

        massUpdatePools();

        // Transfer pending tokens
        // to user
        updateAndPayOutPending(_pid, msg.sender);

        //Transfer in the amounts from user
        // save gas
        if (_amount > 0) {
            pool.token.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount += _amount;
        }

        user.rewardDebt = (user.amount * pool.accEthPerShare) / 1e12;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Test coverage
    // [x] Does user get the deposited amounts?
    // [x] Does user that its deposited for update correcty?
    // [x] Does the depositor get their tokens decreased
    function depositFor(address _depositFor, uint256 _pid, uint256 _amount) public lock {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_depositFor];

        massUpdatePools();

        // Transfer pending tokens
        // to user
        updateAndPayOutPending(_pid, _depositFor); // Update the balances of person that amount is being deposited for

        if (_amount > 0) {
            pool.token.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount += _amount; // This is depositedFor address
        }

        user.rewardDebt = (user.amount * pool.accEthPerShare) / 1e12;

        /// This is deposited for address
        emit Deposit(_depositFor, _pid, _amount);
    }

    // Withdraw  tokens from NXDStakingVault.
    function withdraw(uint256 _pid, uint256 _amount, bool acceptsPenalty) public lock {
        _withdraw(_pid, _amount, msg.sender, msg.sender, acceptsPenalty);
    }

    // Low level withdraw function
    function _withdraw(uint256 _pid, uint256 _amount, address from, address to, bool acceptsPenalty) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (!pool.withdrawable) {
            revert WithdrawDisabled();
        }
        UserInfo storage user = userInfo[_pid][from];
        if (user.amount < _amount) {
            revert Underflow();
        }
        uint256 userGetsAfterPenalty = _amount;

        massUpdatePools();
        updateAndPayOutPending(_pid, from); // Update balances of from. This is not withdrawal but claiming ETH farmed

        WithdrawalRequest storage request = withdrawalRequests[_pid][msg.sender];

        if (_amount > 0) {
            // Stop receiving rewards for this amount NOW
            user.amount = user.amount - _amount;

            if (acceptsPenalty) {
                userGetsAfterPenalty = (_amount * 7500) / 10000;
            } else {
                // 0 means Needs to wait 24 hours
                if (request.canWithdrawAfterTimestamp == 0) {
                    uint256 timestamp = block.timestamp + WITHDRAWAL_COOLDOWN;
                    withdrawalRequests[_pid][msg.sender] = WithdrawalRequest(_amount, timestamp);
                    user.rewardDebt = (user.amount * pool.accEthPerShare) / 1e12;
                    emit WithdrawRequested(from, _amount, timestamp);
                    return;
                } else {
                    revert Cooldown();
                }
            }

            // If we are here we can withdraw

            pool.token.safeTransfer(address(to), userGetsAfterPenalty);

            // Burn penalty amount
            if (userGetsAfterPenalty < _amount) {
                nxd.transfer(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF, _amount - userGetsAfterPenalty);
            }
        }
        user.rewardDebt = (user.amount * pool.accEthPerShare) / 1e12;

        emit Withdraw(to, _pid, _amount);
    }

    /**
     * @notice  Withdraws the amount requested if the cooldown period has passed. If the user has not requested a withdrawal or the cooldown period has not passed, the function reverts.
     * @param   _pid  The pool id.
     */
    function withdrawCooldown(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        WithdrawalRequest storage request = withdrawalRequests[_pid][msg.sender];
        if (request.canWithdrawAfterTimestamp == 0 || request.amount == 0) {
            revert NoRequest();
        }
        if (block.timestamp < request.canWithdrawAfterTimestamp) {
            revert Cooldown();
        }
        uint256 amount = request.amount;
        request.canWithdrawAfterTimestamp = 0;
        request.amount = 0;

        pool.token.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, _pid, request.amount);
    }

    function updateAndPayOutPending(uint256 _pid, address from) internal {
        uint256 pending = pendingETH(_pid, from);

        if (pending > 0) {
            safeETHTransfer(from, pending);
        }
        nxdProtocol.collectFees();
        nxdProtocol.stakeOurDXN();
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // !Caution this will remove all your pending rewards!
    function emergencyWithdraw(uint256 _pid) public lock {
        PoolInfo storage pool = poolInfo[_pid];
        if (!pool.withdrawable) {
            revert WithdrawDisabled();
        }
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.token.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        // No mass update dont update pending rewards
    }

    // Safe eth transfer function
    function safeETHTransfer(address _to, uint256 _amount) internal {
        console.log("safeETHTransfer Sending %s ETH now", _amount);
        console.log("safeETHTransfer Our balance before : %s", address(this).balance);
        (bool sent,) = _to.call{value: _amount}("");
        if (!sent) {
            revert SendETHFail();
        }
        ourETHBalance = address(this).balance;
        console.log("safeETHTransfer Our balance after : %s", address(this).balance);

        //Avoids possible recursion loop
        // proxy?
    }

    /**
     * @dev Receives ETH from NXDProtocol and updates pending rewards.
     */
    receive() external payable {
        console.log("NXDStakingVault: Received %s ETH", msg.value);
        addPendingRewards();
    }
}
