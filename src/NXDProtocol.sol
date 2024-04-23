pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";
import "./interfaces/IDBXen.sol";
// import "./v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/SwapRouter.sol";
import "./interfaces/IV3Oracle.sol";

import "./interfaces/INXDStakingVault.sol";
import "./V2Oracle.sol";
import "./NXDERC20.sol";
import "./NXDStakingVault.sol";
import "./Vesting.sol";
import "./dbxen/interfaces/IDBXenViews.sol";
// import "./uniswapv2/interfaces/IUniswapV2Factory.sol";

/**
 * @dev     Implementation of a fundraiser contract for the NXD Protocol.
 *          This contract will accept DXN and mint NXD at a rate that decreases linearly over time.
 *          The Capped Staking Period (CSP) will run for 14 days, starting at a rate of 1 DXN = 1 NXD and ending at a rate of 1 DXN = 0.5 NXD.
 */
contract NXDProtocol {
    error NotInitialized();
    error PoolAlreadyCreated();
    error GotNothing();
    error InvalidAmount();
    error SendETHFail();
    error CSPOngoing();
    error NoAutoReferral();
    error CSPHasEnded();
    error ReferralCodeAlreadySet();
    error InvalidReferralCode();
    error NoRewards();
    error NXDMaxSupplyMinted();
    error NotAuthorized();

    event PoolCreated(address uniswapV2Pair, uint256 nxdDesired, uint256 dxnDesired);
    event Deposit(address indexed from, uint256 amount, uint256 amountReceived, uint256 referralCode);
    event ReferralCodeSet(uint256 referralCode, address indexed user);
    event ReferralRewardsWithdrawn(address indexed user, uint256 amount);
    event HandleRewards(
        uint256 ethReceived,
        uint256 dxnAmountReceived,
        uint256 dxnBurned,
        uint256 dxnToStake,
        uint256 nxdBurned,
        uint256 ethToStakingVault
    );

    IERC20 public dxn = block.chainid == 11155111
        ? IERC20(0x9d5DD5d3781e758199b9952f70Ede1832e56c985) // DXN token
        : IERC20(0x80f0C1c49891dcFDD40b6e0F960F84E6042bcB6F);

    IDBXen public immutable dbxen;

    NXDERC20 public immutable nxd;

    NXDStakingVault public immutable nxdStakingVault;

    ISwapRouter public UNISWAP_V3_ROUTER = ISwapRouter(payable(0xE592427A0AEce92De3Edee1F18E0157C05861564));

    IUniswapV2Router02 public UNISWAP_V2_ROUTER = block.chainid == 11155111
        ? IUniswapV2Router02(0x42f6460304545B48E788F6e8478Fbf5E7dd7CDe0)
        : IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public UNISWAP_V2_FACTORY = block.chainid == 11155111
        ? 0xdAF1b15AC3CA069Bf811553170Bad5b23342A4D6
        : 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant DXN_WETH_POOL = 0x7F808fD904FFA3eb6A6F259e6965Fb1466A05372;

    address public constant DEADBEEF = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

    uint256 initialRate = 1 ether; // starts 1:1 DXN:NXD (1 DXN = 1 NXD)
    uint256 finalRate = 0.5 ether; //  ends 1:0.5 DXN:NXD (1 DXN = 0.5 NXD)
    uint256 public startTime = block.timestamp;
    uint256 public endTime = startTime + 14 days;
    // calculated using the following formula = ((initialRate - finalRate) * 1e18) / (endTime - startTime);
    uint256 public constant decreasePerSecond = 413359788359788359788359788360;
    mapping(uint256 => address) public referralCodes;
    mapping(address => uint256) public userToReferralCode;
    mapping(address => uint256) public referredRewards;
    mapping(address => uint256) public referrerRewards;
    // for ui purposes
    mapping(address => uint256) public userTotalMintedNoBonus;

    IDBXenViews public immutable dbxenViews;
    // TWAP Oracle for DXN/WETH pair
    IV3Oracle public immutable v3Oracle;
    // Simple TWAP Oracle for NXD/DXN pair
    V2Oracle public v2Oracle;

    uint256 public pendingDXNToStake;

    Vesting public immutable vesting;

    address public devAllocMinter;

    uint256 public totalUnclaimedReferralRewards;

    constructor(
        uint256 initialSupply,
        address _dbxen,
        address _dbxenViews,
        address _v3Oracle,
        address _governance,
        address _devFeeTo,
        address _devAllocMinter
    ) {
        dbxen = IDBXen(_dbxen);
        vesting = new Vesting();
        nxd = new NXDERC20(initialSupply, msg.sender, IERC20(dxn), _governance, address(vesting), _devFeeTo); // deployer gets initial supply of NXD to create LP
        vesting.setToken(address(nxd));
        nxdStakingVault = new NXDStakingVault(nxd);
        // NXD is whitelisted for tax when sending and when receiving.
        nxd.updateTaxWhitelist(address(nxdStakingVault), true, true);

        dbxenViews = IDBXenViews(_dbxenViews);
        v3Oracle = IV3Oracle(_v3Oracle);

        devAllocMinter = _devAllocMinter;
    }

    /**
     * @dev     Creates a pool for the NXD/DXN pair and initializes the V2Oracle contract. Reverts if the pool has already been created. This can only be called by deployer of this contract as they are the only ones who have NXD to create the pool.
     * @param   nxdDesired  NXD desired to add to the pool.
     * @param   dxnDesired  DXN desired to add to the pool.
     * @param   to  LP token recipient.
     * @param   deadline  Deadline for the transaction.
     */
    function createPool(uint256 nxdDesired, uint256 dxnDesired, address to, uint256 deadline)
        external
        returns (uint256 liquidity)
    {
        if (nxdDesired == 0 || dxnDesired == 0) {
            revert InvalidAmount();
        }
        if (address(v2Oracle) != address(0x0)) {
            revert PoolAlreadyCreated();
        }
        nxd.transferFrom(msg.sender, address(this), nxdDesired);
        dxn.transferFrom(msg.sender, address(this), dxnDesired);

        nxd.approve(address(UNISWAP_V2_ROUTER), nxdDesired);
        dxn.approve(address(UNISWAP_V2_ROUTER), dxnDesired);
        // Create a pool for the NXD/DXN pair
        (,, liquidity) =
            UNISWAP_V2_ROUTER.addLiquidity(address(nxd), address(dxn), nxdDesired, dxnDesired, 0, 0, to, deadline);
        // Initialize the V2Oracle contract
        v2Oracle = new V2Oracle(UNISWAP_V2_FACTORY, address(nxd), address(dxn));
        address uniswapV2Pair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(address(nxd), address(dxn));
        // Set the pair and oracle for the NXD contract
        nxd.setUniswapV2Pair(uniswapV2Pair);
        nxd.setV2Oracle(address(v2Oracle));
        emit PoolCreated(uniswapV2Pair, nxdDesired, dxnDesired);
    }

    /**
     * @dev Returns the current rate of DXN to NXD.
     */
    function currentRate() public view returns (uint256) {
        uint256 secondsPassed = block.timestamp - startTime;
        return ((initialRate) - ((secondsPassed * decreasePerSecond)) / 1e18);
    }

    /**
     * @dev Returns the amount of DXN that this contract has earned in fees in the DBXen Protocol.
     */
    function ourClaimableFees() public view returns (uint256) {
        return dbxenViews.getUnclaimedFees(address(this));
    }

    /**
     * @dev     Returns the referral bonuses for the referrer and the user.
     * @param   amount  The amount of DXN to deposit.
     * @return  referrerAmount  referrerAmount The amount of NXD to be minted as a referral bonus for the referrer.
     * @return  userAmount  userAmount The amount of NXD to be minted as a referral bonus for the user.
     */
    function getReferralBonuses(uint256 amount) public pure returns (uint256 referrerAmount, uint256 userAmount) {
        referrerAmount = (amount * 5000) / 100000;
        userAmount = (amount * 10000) / 100000;
    }

    /**
     * @dev Deposits DXN and mints NXD. If a referral code is provided, the referrer will receive a 5% bonus. The user will receive a 10% bonus. Reverts if the fundraiser has ended or minted NXD exceeds max supply.
     * @param _amount The amount of DXN to deposit.
     * @param _referralCode The referral code of the user who referred this user. 0 if no referral.
     * @param _allowDynamicAmount If true, the amount of DXN to deposit will be adjusted based on whether the max supply of NXD will be exceeded. If false, the amount will not be adjusted and the transaction will revert if the max supply of NXD will be exceeded.
     */
    function deposit(uint256 _amount, uint256 _referralCode, bool _allowDynamicAmount) external {
        if (address(v2Oracle) == address(0x0)) {
            revert NotInitialized();
        }

        if (block.timestamp > endTime) {
            revert CSPHasEnded();
        }
        if (_amount == 0) {
            revert InvalidAmount();
        }
        uint256 _currentRate = currentRate();
        uint256 amountReceived = (_amount * _currentRate) / 1e18;
        uint256 referrerAmount = 0;
        uint256 userBonusAmount = 0;
        address referrer = referralCodes[_referralCode];

        if (referrer == msg.sender) {
            revert NoAutoReferral();
        }

        // Check if referral code is valid
        if (referrer != address(0x0)) {
            // // 5% referral bonus
            // // 10% bonus for referred users
            (referrerAmount, userBonusAmount) = getReferralBonuses(amountReceived);
        }

        // Check that amounts do not exceed max supply
        if (
            nxd.totalSupply() + amountReceived + referrerAmount + userBonusAmount
                > nxd.maxSupply() - nxd.MAX_DEV_ALLOC() - totalUnclaimedReferralRewards
        ) {
            // Change the _amount to the amount that can be minted without exceeding max supply
            uint256 remainingSupply =
                nxd.maxSupply() - nxd.totalSupply() - nxd.MAX_DEV_ALLOC() - totalUnclaimedReferralRewards;
            if (remainingSupply == 0 || !_allowDynamicAmount) {
                revert NXDMaxSupplyMinted();
            }

            // amountReceived is maximum amount of NXD before bonuses that the user can mint.
            // if has referrer then take into consideration 15% bonus (10% for user, 5% for referrer)
            amountReceived = referrer != address(0x0)
                ? remainingSupply
                    - ((((remainingSupply * 1.15 ether - (remainingSupply * 1e18)) * 1e18) / 1.15 ether) / 1e18) // Doing it this way to avoid precision  loss errors
                : remainingSupply;

            // Get the amount of DXN that needs to be deposited to mint the remaining supply of NXD.
            _amount = (amountReceived * 1e18) / _currentRate;
            // Recalculate bonuses
            (referrerAmount, userBonusAmount) = getReferralBonuses(amountReceived);
            console.log("_amount: %s", _amount);
            console.log("amountReceived: %s", amountReceived);
            console.log("referrerAmount: %s", referrerAmount);
            console.log("userBonusAmount: %s", userBonusAmount);
            console.log(
                "amountReceived+referrerAmount+userBonusAmount: %s", amountReceived + referrerAmount + userBonusAmount
            );
        }

        referrerRewards[referrer] += referrerAmount;
        referredRewards[msg.sender] += userBonusAmount;

        totalUnclaimedReferralRewards += referrerAmount + userBonusAmount;

        userTotalMintedNoBonus[msg.sender] += amountReceived;

        _transferFromAndStake(_amount);

        nxd.mint(msg.sender, amountReceived);

        collectFees();
        stakeOurDXN();

        emit Deposit(msg.sender, _amount, amountReceived, _referralCode);
    }

    /**
     * @dev     Allows users to deposit DXN and stakes it in the DBXen contract. Does not mint NXD. Does not care if CSP has ended.
     * @param   _amount  The amount of DXN to deposit.
     */
    function depositNoMint(uint256 _amount) external {
        _transferFromAndStake(_amount);
        emit Deposit(msg.sender, _amount, 0, 0);
        collectFees();
        stakeOurDXN();
    }

    /**
     * @notice  Internal function that transfers DXN from the sender to this contract and stakes it in the DBXen contract. Used in `deposit` and `depositNoMint` functions.
     * @param   _amount  The amount of DXN to transfer and stake.
     */
    function _transferFromAndStake(uint256 _amount) internal {
        dxn.transferFrom(msg.sender, address(this), _amount);
        dxn.approve(address(dbxen), _amount);
        dbxen.stake(_amount);
    }

    /**
     * @dev     Sets the referral code for the sender.
     * @param   _referralCode  The referral code to set. Must be unique.
     */
    function setReferralCode(uint256 _referralCode) external {
        if (_referralCode == 0) {
            revert InvalidReferralCode();
        }
        if (referralCodes[_referralCode] != address(0x0)) {
            revert ReferralCodeAlreadySet();
        }
        referralCodes[_referralCode] = msg.sender;
        userToReferralCode[msg.sender] = _referralCode;

        emit ReferralCodeSet(_referralCode, msg.sender);
    }

    /**
     * @dev Collects fees from the DBXen contract.
     * Can be called by anyone.
     */
    function collectFees() public {
        if (ourClaimableFees() > 0) {
            // Need to check because claimFees() will revert if there are no fees to claim
            dbxen.claimFees();
        }
    }

    /**
     * @dev     Withdraws referral rewards for the sender. Reverts if there are no rewards to withdraw or if the fundraiser is ongoing. Rewards are minted as NXD.
     */
    function withdrawReferralRewards() external {
        if (block.timestamp < endTime) {
            revert CSPOngoing();
        }
        uint256 amount = referredRewards[msg.sender] + referrerRewards[msg.sender];
        if (amount == 0) {
            revert NoRewards();
        }
        totalUnclaimedReferralRewards -= amount;
        referrerRewards[msg.sender] = 0;
        referredRewards[msg.sender] = 0;
        nxd.mint(msg.sender, amount);
        emit ReferralRewardsWithdrawn(msg.sender, amount);
    }

    /**
     * @dev     Stakes our DXN in the DBXen contract. Can be called by anyone. Having this in the receive() function will cause a ReentrancyGuardReentrantCall error.
     */
    function stakeOurDXN() public {
        uint256 amount = pendingDXNToStake;
        if (amount > 0) {
            pendingDXNToStake = 0;
            dxn.approve(address(dbxen), amount);
            dbxen.stake(amount);
        }
    }

    function setDevAllocMinter(address newDevAllowMinter) external {
        if (msg.sender != devAllocMinter) revert NotAuthorized();
        devAllocMinter = newDevAllowMinter;
    }
    /**
     * @dev    Mints NXD for the dev allocation and distributes it to the recipients. Can only be called by the devAllocMinter.
     */

    function mintDevAlloc(address[] memory recipients) public {
        if (msg.sender != devAllocMinter) revert NotAuthorized();
        if (block.timestamp < endTime) {
            revert CSPOngoing();
        }

        uint256 totalNXDMinted = nxd.totalSupply() + totalUnclaimedReferralRewards;
        // dev alloc is 2% of total minted
        console.log("mintDevAlloc totalNXDMinted = ", totalNXDMinted);
        uint256 devAlloc = ((totalNXDMinted * 10000) / 9800) - totalNXDMinted;
        console.log("mintDevAlloc devAlloc = ", devAlloc);

        if (devAlloc > 0) {
            if (devAlloc + totalNXDMinted > nxd.maxSupply()) {
                devAlloc = nxd.maxSupply() - totalNXDMinted;
            }

            nxd.mintDevAlloc(address(this), devAlloc);
            nxd.transfer(address(vesting), devAlloc);
            uint256 devAllocPerRecipient = devAlloc / recipients.length;

            for (uint256 i = 0; i < recipients.length; i++) {
                vesting.setVesting(recipients[i], devAllocPerRecipient);
            }
        }
    }

    /**
     * @dev Receives ETH from DBXen after calling `collectFees` and uses it to buy DXN, stake half of it, and burn the other half.
     * This is needed to receive ETH from DBXen.claimFees()
     * ETH rewards earned through the DXN Staking Vault are distributed as followed:
     * • 50% Buy & Burn NXD
     * • 30% Buy & Stake DXN
     * • 15% NXD Staking Vault
     * • 5% Buy & Burn DXN
     *
     */
    receive() external payable {
        //         DXN Staking Vault
        // • 50% Buy & Burn NXD
        // • 30% Buy & Stake DXN
        // • 15% NXD Staking Vault
        // • 5% Buy & Burn DXN

        // Buy DXN with 85% of ETH received. 30% to Buy & Stake DXN + 50% to Buy & Burn NXD + 5% to Buy & Burn DXN
        uint256 ethToSwapForDXN = (address(this).balance * 8500) / 10000;

        uint256 dxnPriceNow = v3Oracle.getHumanQuote(DXN_WETH_POOL, 0, 1 ether, address(dxn), WETH9);
        console.log("Before Swap: 1 DXN = %s ETH", dxnPriceNow);
        uint256 quote = v3Oracle.getHumanQuote(DXN_WETH_POOL, 5 minutes, 1 ether, WETH9, address(dxn));
        uint256 minOut = (ethToSwapForDXN * quote) / 1e18;
        // - 3%
        minOut = (minOut * 9700) / 10000;
        uint256 dxnAmountReceived = UNISWAP_V3_ROUTER.exactInputSingle{value: ethToSwapForDXN}(
            ISwapRouter.ExactInputSingleParams(
                WETH9, address(dxn), 10000, address(this), block.timestamp, ethToSwapForDXN, minOut, 0
            )
        );

        // Burn 5/85 of DXN received (= 5% of ETH received)
        uint256 dxnToBurn = (dxnAmountReceived * 11111111) / 100000000;

        dxn.transfer(DEADBEEF, dxnToBurn);

        // Sell DXN for NXD. Sell (50/85) % of DXN received. (50% of total ETH received)
        uint256 dxnToSwapForNXD = (dxnAmountReceived * 58823529) / 100000000;
        console.log("dxnToSwapForNXD = ", dxnToSwapForNXD);
        if (v2Oracle.canUpdate()) {
            v2Oracle.update();
        }
        // Buy NXD with remaining DXN
        uint256 amountOutMin = v2Oracle.consult(address(dxn), dxnToSwapForNXD);
        // - 3%
        amountOutMin = (amountOutMin * 9700) / 10000;
        address[] memory path = new address[](2);
        path[0] = address(dxn);
        path[1] = address(nxd);

        dxn.approve(address(UNISWAP_V2_ROUTER), dxnToSwapForNXD);

        uint256[] memory amounts = UNISWAP_V2_ROUTER.swapExactTokensForTokens(
            dxnToSwapForNXD, amountOutMin, path, address(this), block.timestamp
        );
        if (amounts[0] == 0) {
            revert GotNothing();
        }
        pendingDXNToStake += dxn.balanceOf(address(this));
        console.log("pendingDXNToStake after swap", pendingDXNToStake);

        // Burn our NXD
        uint256 nxdToBurn = nxd.balanceOf(address(this));
        nxd.transfer(DEADBEEF, nxdToBurn);
        uint256 ethToStakingVault = address(this).balance;
        console.log("Sending %S ETH to Staking Vault: ", address(this).balance);
        // Send remaining ETH to the NXD Staking Vault
        (bool sent,) = address(nxdStakingVault).call{value: address(this).balance}("");
        if (!sent) {
            revert SendETHFail();
        }

        emit HandleRewards(msg.value, dxnAmountReceived, dxnToBurn, pendingDXNToStake, nxdToBurn, ethToStakingVault);
        // nxdStakingVault.addPendingRewards();
    }
}
