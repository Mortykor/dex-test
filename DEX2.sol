// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "Ownable.sol";
import "Address.sol";
import "SafeERC20.sol";
import "SafeIERC20.sol";
import "SafeMath.sol";

interface IRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

contract Dex is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint public feePercent = 25; // 0.25%

    address public feeAccount;
    address public router;
    address public weth;

    mapping(address => bool) public whitelistedTokens;

    constructor(address _feeAccount, address _router, address _weth) {
        feeAccount = _feeAccount;
        router = _router;
        weth = _weth;
    }

    function swapTokens(address _tokenA, address _tokenB, uint256 _amountIn) external payable {
        address[] memory path = new address[](2);
        if (_tokenA == address(0)) {
            path[0] = weth;
            path[1] = _tokenB;
        } else if (_tokenB == address(0)) {
            path[0] = _tokenA;
            path[1] = weth;
        } else {
            path[0] = _tokenA;
            path[1] = _tokenB;
        }

        _proceedToUniswap(_tokenA, _tokenB, _amountIn, path);
    }

    function customSwapTokens(address _tokenA, address _tokenB, uint256 _amountIn, address[]memory path) external payable{
        if (_tokenA == address(0)) {
            require(weth == path[0] && _tokenB == path[path.length - 1], "EquiDEX: Path must be specified");
        } else if (_tokenB == address(0)) {
            require(_tokenA == path[0] && weth == path[path.length - 1], "EquiDEX: Path must be specified");
        } else {
            require(_tokenA == path[0] && _tokenB == path[path.length - 1], "EquiDEX: Path must be specified");
        }
        _proceedToUniswap(_tokenA, _tokenB, _amountIn, path);
    }

    function _proceedToUniswap(address _tokenA, address _tokenB, uint256 _amountIn, address[]memory path) internal {
        require(_amountIn > 0, "EquiDEX: amountIn must be greater than 0");
        require(whitelistedTokens[_tokenA], "EquiDEX: TokenA is not whitelisted");
        if (_tokenA == address(0)) {
            require (_amountIn >= msg.value, "EquiDEX: Insufficient ETH");
            uint fee = _amountIn * feePercent / 10000;
            payable(feeAccount).transfer(fee);
            uint amountToSwap = _amountIn - fee;
            _swapBNBForTokens(amountToSwap, path);
        } else{
            uint256 allowance = IERC20(_tokenA).allowance(msg.sender, address(this));
            require(allowance >= _amountIn, "EquiDEX: Insufficient allowance for token transfer");
            
            IERC20(_tokenA).safeTransferFrom(msg.sender, address(this), _amountIn);
            uint fee = _amountIn * feePercent / 10000;
            IERC20(_tokenA).safeTransfer(feeAccount, fee);
            uint amountToSwap = _amountIn - fee;
            if (_tokenB == address(0)) {
                _swapTokensForBNB(amountToSwap, path);
            } else {
                _swapTokensForTokens(amountToSwap, path);
            }
        }
    }

    function _approve(address _token, uint _amount) internal {
        IERC20(_token).approve(address(router), _amount);
    }

    function _swapTokensForBNB(uint _amount, address[]memory path) internal {
        IRouter(router).swapExactTokensForETH(
            _amount,
            0,
            path,
            msg.sender,
            block.timestamp
        );
    }

    function _swapBNBForTokens(uint _amount, address[]memory path) internal {
        IRouter(router).swapExactETHForTokens{ value: _amount }(
            0,
            path,
            msg.sender,
            block.timestamp
        );
    }

    function _swapTokensForTokens(uint _amount, address[]memory path) internal {
        IRouter(router).swapExactTokensForTokens(
            _amount,
            0,
            path,
            msg.sender,
            block.timestamp
        );
    }

    function getOutputTokenAmount(uint inputAmount, address[]memory path) external view returns (uint outputAmount) {
        uint[]memory outputs = IRouter(router).getAmountsOut(inputAmount, path);
        return outputs[outputs.length - 1];
    }

    function setFeePercent(uint _feePercent) external onlyOwner {
        feePercent = _feePercent;
    }

    function setFeeAccount(address _feeAccount) external onlyOwner {
        feeAccount = _feeAccount;
    }

    function setRouterweth(address _router, address _weth) external onlyOwner {
        router = _router;
        weth = _weth;
    }

    function addWhitelistedTokens(address[]memory _tokens) external onlyOwner {
        for (uint i = 0; i < _tokens.length; i++) {
            whitelistedTokens[_tokens[i]] = true;
            if (_tokens[i] != address(0)) {
                _approve(_tokens[i], type(uint256).max);
            }
        }
    }

    function removeWhitelistedTokens(address[]memory _tokens) external onlyOwner {
        for (uint i = 0; i < _tokens.length; i++) {
            whitelistedTokens[_tokens[i]] = false;
        }
    }

    function approveTokens(address[]memory _tokens, uint[] memory _amounts) external onlyOwner {
        for (uint i = 0; i < _tokens.length; i++) {
            _approve(_tokens[i], _amounts[i]);
        }
    }

    function emergencyWithdraw(address _token, uint _amount) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function emergencyWithdrawETH(uint _amount) external onlyOwner {
        payable(owner()).transfer(_amount);
    }
}