// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "./libraries/SafeMath.sol";

abstract contract ERC20 is IERC20 {
    using SafeMath for uint256;
    
    mapping(address => uint256) internal _balances;

    mapping(address => mapping(address => uint256)) internal _allowances;

    uint256 internal _totalSupply;

    string internal _name;

    string internal _symbol;

    uint8 internal _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
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

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance")
        );
        
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero")
        );
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account_, uint256 amount_) internal virtual {
        require(account_ != address(0), "ERC20: mint to the zero address");
        _beforeTokenTransfer(address(this), account_, amount_);
        _totalSupply = _totalSupply.add(amount_);
        _balances[account_] = _balances[account_].add(amount_);
        emit Transfer(address(this), account_, amount_);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(address from_, address to_, uint256 amount_) internal virtual {}
}


contract VaultOwned is AccessControl {
    bytes32 public constant MINT = keccak256("MINT");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyVault() {
        require(hasRole(MINT, msg.sender), "VaultOwned: caller is not the Vault");
        _;
    }
}

interface IFeeReceiver {
    function triggerSwapFeeForLottery() external;
}


contract OLYERC20Token is ERC20, VaultOwned {
    using SafeMath for uint256;

    constructor() ERC20("OLY", "OLY", 9) {}

    function mint(address account_, uint256 amount_) external onlyVault {
        _mint(account_, amount_);
    }

    function burn(uint256 amount) public virtual {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account_, uint256 amount_) public virtual {
        _burnFrom(account_, amount_);
    }

    function _burnFrom(address account_, uint256 amount_) internal virtual {
        uint256 decreasedAllowance_ =
            allowance(account_, msg.sender).sub(amount_, "ERC20: burn amount exceeds allowance");

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }
}


contract OLY is OLYERC20Token {
    using SafeMath for uint256;

    address public mainPair;
    address public feeReceiver;

    uint256 public constant PRECISION = 100 * 1e3;
    uint256 public feeRatio = 3 * 1e3;
    uint256 public buyFeeRatio;

    bytes32 public constant INTERN_SYSTEM = keccak256("INTERN_SYSTEM");

    event FeeRatioChanged(uint8 _ratioType,uint256 ratio);
    event FeeTaken(address indexed payer, address indexed receiver, uint256 left, uint256 fee);

    modifier onlyDefaultAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        _;
    }

    constructor(address _feeReceiver, uint _buyFeeRatio) OLYERC20Token() {
        require(_feeReceiver != address(0), "Invalid fee receiver");
        require(_buyFeeRatio <= PRECISION, "Invalid buy fee ratio");

        feeReceiver = _feeReceiver;
        buyFeeRatio = _buyFeeRatio;

        _grantRole(INTERN_SYSTEM, msg.sender);
        _grantRole(INTERN_SYSTEM, _feeReceiver);
    }

    function setMainPair(address pair) external onlyDefaultAdmin {
        mainPair = pair;
    }

    function setRatio(uint8 ratioType,uint256 ratio) external onlyDefaultAdmin {
        require(ratio <= PRECISION, "Exceeds precision");
        if(ratioType == 0){
            buyFeeRatio = ratio;
        } else {
            feeRatio = ratio;
        }
        emit FeeRatioChanged(ratioType,ratio);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        
        _beforeTokenTransfer(sender, recipient, amount);
        
        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        
        // take fee when non-whitelist users trade
        if (_isTradeAndNotInSystem(sender, recipient)) {
            // buyer or remove lp
            
            if (sender == mainPair) {
                uint buyFee = amount.mul(buyFeeRatio).div(PRECISION);
                
                if(buyFee > 0){
                    amount = amount - buyFee;
                    _balances[feeReceiver] += buyFee;

                    emit Transfer(sender, feeReceiver, buyFee);
                }
            }
            // seller or add lp
            else if(recipient == mainPair){
                // take fee
                uint256 fee = amount.mul(feeRatio).div(PRECISION);
                if (fee > 0) {
                    amount = amount - fee;
                    _balances[feeReceiver] += fee;

                    emit Transfer(sender, feeReceiver, fee);
                    emit FeeTaken(sender, feeReceiver, amount, fee);
                    IFeeReceiver(feeReceiver).triggerSwapFeeForLottery();
                }
            }
        }
        
        _balances[recipient] = _balances[recipient].add(amount);
        
        emit Transfer(sender, recipient, amount);
    }

    function _isTradeAndNotInSystem(address _from, address _to) internal view returns (bool) {
        return (_from == mainPair && !hasRole(INTERN_SYSTEM,_to)) || (_to == mainPair && !hasRole(INTERN_SYSTEM,_from));
    }
}
