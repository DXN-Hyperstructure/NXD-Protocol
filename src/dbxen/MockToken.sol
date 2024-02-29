pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IBurnableToken.sol";
contract MockToken is ERC20, IBurnableToken {
    uint8 public tokenDecimals;

    constructor(
        uint256 initialSupply,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, initialSupply);
        tokenDecimals = _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return tokenDecimals;
    }

    function burn(address user, uint256 amount) public override {
        _burn(user, amount);
    }
}
