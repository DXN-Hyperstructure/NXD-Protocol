pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IV2Oracle.sol";
import "./interfaces/INXDProtocol.sol";
import "./TaxRecipient.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "forge-std/console.sol";

interface IUniV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/**
 * @dev     NXD Token contract that implements the ERC20 standard. It also includes:
 *          - A tax mechanism for selling NXD tokens.
 *          - A mechanism to remove NXD tokens from unauthorized LPs. Only called by the governance
 *          - A mechanism to mint NXD tokens Only by the protocol contract.
 *          - A mechanism to set the Uniswap V2 pair address and the V2 Oracle address. Only by the protocol contract.
 *          - A mechanism to remove NXD tokens from unauthorized LPs. Only by the governance.
 */
contract NXDERC20 is Context, IERC20, IERC20Metadata, IERC20Errors {
    error Unauthorized();
    error NoRemovalZeroAddress();
    error NoLPWithdraw();
    error MaxSupply();
    error NoRemovalMainLP();

    mapping(address account => uint256) private _balances;

    mapping(address account => mapping(address spender => uint256)) private _allowances;

    address public constant DEADBEEF = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * The address of the NXDProtocol.sol contract instance.
     */
    address public immutable protocol;

    uint256 public constant SELL_TAX_X100 = 500; // 5%

    struct TaxWhitelist {
        bool isExcludedWhenSender;
        bool isExcludedWhenRecipient;
    }

    // Whitelist for tax exclusion. address => (isExcludedWhenSender, isExcludedWhenRecipient)
    mapping(address => TaxWhitelist) public isExcludedFromTax;

    mapping(address => uint256) public lpSupplyOfPair;

    IUniV2Factory public UNISWAP_V2_FACTORY = IUniV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 public UNISWAP_V2_ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    IUniswapV3Factory public UNISWAP_V3_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    IUniswapV2Pair public uniswapV2Pair;
    IV2Oracle public v2Oracle;

    IERC20 public dxn;
    // Max to be minted as rewards for staking DXN
    uint256 public constant MAX_REWARDS_SUPPLY = 730_000 ether; // 730k NXD
    // Max to be minted for dev alloc (2% of total supply)
    uint256 public constant MAX_DEV_ALLOC = 15_000 ether; // 15k NXD
    // Max rewards supply + initial supply for liquidity
    uint256 public immutable maxSupply;

    TaxRecipient public immutable taxRecipient;

    uint256 public lastSupplyOfNXDInPair;
    uint256 public lastSupplyOfDXNInPair;
    address public governance;

    address public devFeeTo;

    modifier onlyGovernance() {
        if (msg.sender != governance) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * Called from within the NXDProtocol.sol constructor.
     */
    constructor(
        uint256 _initialSupply,
        address _initialSupplyTo,
        IERC20 _dxn,
        address _governance,
        address _vesting,
        address _devFeeTo
    ) {
        _name = block.chainid == 1 ? "NXD Token" : "";
        _symbol = block.chainid == 1 ? "NXD" : "";

        protocol = msg.sender;
        devFeeTo = _devFeeTo;

        _mint(_initialSupplyTo, _initialSupply);

        dxn = _dxn;

        maxSupply = _initialSupply + MAX_REWARDS_SUPPLY + MAX_DEV_ALLOC;

        taxRecipient = new TaxRecipient(msg.sender);

        governance = _governance;

        _updateTaxWhitelist(address(this), true, false);
        _updateTaxWhitelist(address(taxRecipient), true, false);
        _updateTaxWhitelist(protocol, true, true);
        _updateTaxWhitelist(_vesting, true, true);
    }

    function setUniswapV2Pair(address _uniswapV2Pair) external {
        if (msg.sender != protocol) {
            revert Unauthorized();
        }
        uniswapV2Pair = IUniswapV2Pair(_uniswapV2Pair);
        taxRecipient.setUniswapV2Pair(_uniswapV2Pair);

        _updateTaxWhitelist(_uniswapV2Pair, true, false);
    }

    function setV2Oracle(address _v2Oracle) external {
        if (msg.sender != protocol) {
            revert Unauthorized();
        }
        v2Oracle = IV2Oracle(_v2Oracle);
    }

    function updateTaxWhitelist(address account, bool whenSender, bool whenRecipient) external {
        // Only governance or protocol can update tax whitelist
        if (msg.sender != governance && msg.sender != protocol) {
            revert Unauthorized();
        }
        _updateTaxWhitelist(account, whenSender, whenRecipient);
    }

    /**
     * @dev     Sets the governance address. Only callable by the current governance. Can be set to the zero address.
     * @param   _governance  The address of the new governance.
     */
    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
    }

    function _updateTaxWhitelist(address account, bool whenSender, bool whenRecipient) internal {
        isExcludedFromTax[account] = TaxWhitelist(whenSender, whenRecipient);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /**
     * @dev Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
     * Relies on the `_update` mechanism
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev Sets `value` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
     * `_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
     * `Approval` event during `transferFrom` operations.
     *
     * Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
     * true using the following override:
     * ```
     * function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
     *     super._approve(owner, spender, value, true);
     * }
     * ```
     *
     * Requirements are the same as {_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }

    function mint(address account, uint256 amount) external {
        if (msg.sender != protocol) {
            revert Unauthorized();
        }
        if (totalSupply() + amount > maxSupply - MAX_DEV_ALLOC) {
            revert MaxSupply();
        }
        _mint(account, amount);
    }

    function mintDevAlloc(address account, uint256 amount) external {
        if (msg.sender != protocol) {
            revert Unauthorized();
        }
        if (totalSupply() + amount > maxSupply) {
            revert MaxSupply();
        }
        _mint(account, amount);
    }

    /**
     * @dev     Returns the amount after tax and the tax amount. Whitelist is:
     *          - When sender is this contract: To be able to swap NXD to DXN in `_transfer_ function.
     *          - When sender is the `protocol` contract: To be able to burn NXD.
     *          - When recipient is the `protocol` contract: To be able to create initial liquidity.
     *          - When sender is the `taxRecipient` contract: To be able to handle tax: adding liquidity to NXD/DXN.
     *          - When sender is the `uniswapV2Pair` contract: No tax on buys.
     * @param   from  The address of the sender.
     * @param   to  The address of the recipient.
     * @param   amount  The amount to calculate the tax for.
     * @return  uint256 The amount after tax.
     * @return  uint256  The tax amount.
     */
    function getAmountsAfterTax(address from, address to, uint256 amount) public view returns (uint256, uint256) {
        if (isExcludedFromTax[from].isExcludedWhenSender || isExcludedFromTax[to].isExcludedWhenRecipient) {
            return (amount, 0);
        }
        // Apply tax
        uint256 taxAmount = (amount * SELL_TAX_X100) / 10000;
        uint256 amountAfterTax = amount - taxAmount;
        return (amountAfterTax, taxAmount);
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }

        if (value > _balances[from]) {
            revert ERC20InsufficientBalance(from, _balances[from], value);
        }

        _balances[from] -= value;
        (uint256 amountAfterTax, uint256 taxAmount) = getAmountsAfterTax(from, to, value);
        console.log("NXDERC20: Amount after tax: %s", amountAfterTax);
        console.log("NXDERC20: taxAmount: %s", taxAmount);
        if (taxAmount > 0) {
            // NXD burn - 2.0%
            // DXN buy and stake - 1.5%
            // LP add - 1%
            // Dev Fee - 0.5%
            _balances[address(this)] += taxAmount;
            address[] memory nxdDXNPath = new address[](2);
            nxdDXNPath[0] = address(this);
            nxdDXNPath[1] = address(dxn);

            // Sell NXD, buy DXN and stake
            uint256 sellNXDAmount = (taxAmount * 4000) / 10000; // 40% (2/5) of total tax amount, which is 1.5% buy and stake DXN + 0.5% buy DXN to add liquidity
            _approve(address(this), address(UNISWAP_V2_ROUTER), sellNXDAmount);
            if (v2Oracle.canUpdate()) {
                v2Oracle.update();
            }
            uint256 amountOutMin = v2Oracle.consult(address(this), sellNXDAmount);
            // - 3%
            amountOutMin = (amountOutMin * 9700) / 10000;

            // Send to taxRecipient to add LP
            UNISWAP_V2_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                sellNXDAmount, amountOutMin, nxdDXNPath, address(taxRecipient), block.timestamp
            );

            console.log("NXDERC20: tax recipient received %s DXN", dxn.balanceOf(address(taxRecipient)));

            // We now have DXN, add liquidity to NXD/DXN pair
            uint256 remainingTax = taxAmount - sellNXDAmount; // 30%
            uint256 burnAmount = (taxAmount * 4000) / 10000; // 2% of all tax. 2/5% of tax amount
            uint256 devFeeAmount = (taxAmount * 1000) / 10000; // 10% of all tax. 0.5/5% of tax amount

            console.log("NXDERC20: remainingTax = ", remainingTax);
            console.log("NXDERC20: burnAmount = ", burnAmount);
            console.log("NXDERC20: Expected NXD amount to add to liq= ", remainingTax - burnAmount);

            _balances[address(this)] -= remainingTax;

            // Burn 10% from tax amount
            _balances[0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF] += burnAmount;
            emit Transfer(from, 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF, burnAmount);
            _balances[devFeeTo] += devFeeAmount;
            emit Transfer(from, devFeeTo, devFeeAmount);

            uint256 amountToTaxHandler = remainingTax - burnAmount - devFeeAmount;

            // Send NXD to Tax recipient to add liquidity
            _balances[address(taxRecipient)] += amountToTaxHandler;
            emit Transfer(from, address(taxRecipient), amountToTaxHandler);
            taxRecipient.handleTax();
        }
        _balances[to] += amountAfterTax;
        emit Transfer(from, to, amountAfterTax);
    }

    function setDevFeeTo(address _devFeeTo) external {
        if (msg.sender != devFeeTo) {
            revert Unauthorized();
        }
        devFeeTo = _devFeeTo;
    }

    function transfer(address to, uint256 value) public virtual override returns (bool) {
        _transfer(_msgSender(), to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        _spendAllowance(from, _msgSender(), value);
        _transfer(from, to, value);
        return true;
    }
}
