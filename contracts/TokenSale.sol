// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./helpers/Whitelist.sol";
import "./interfaces/IUniswapRouterV2.sol";

pragma solidity 0.8.17;

contract TokenSale is Ownable, Whitelist {
    using SafeERC20 for IERC20;
    using Address for address;

    IUniswapV2Router public swapRouter;

    enum RoundsTypes {
        PRE_SALE,
        MAIN_SALE,
        PRIVATE_SALE
    }

    struct TokenSaleRound {
        uint256 startTime;
        uint256 endTime;
        uint256 duration;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 purchasePrice;
        uint256 tokensSold;
        uint256 totalPurchaseAmount;
        bool isPublic;
        bool isEnded;
    }

    address public planetexToken;
    address public usdtToken;
    address[] public path;
    address public treasury;
    uint256 public roundsCounter;
    uint256 public immutable PRECISSION = 100;

    mapping(uint256 => TokenSaleRound) public rounds; // 0 pre_sale; 1 main_sale; 2 private_sale;
    mapping(address => mapping(uint256 => uint256)) public userBalance;
    mapping(address => mapping(uint256 => uint256)) public userSpentFunds;

    constructor(
        address _planetexToken,
        uint256[] memory _purchaseAmounts,
        uint256[] memory _minAmounts,
        uint256[] memory _maxAmounts,
        uint256[] memory _durations,
        uint256[] memory _purchasePrices,
        bool[] memory _isPublic,
        address _usdtToken,
        address _treasury,
        address _unirouter
    ) {
        for (uint256 i; i < _purchaseAmounts.length; i++) {
            TokenSaleRound storage tokenSaleRound = rounds[i];
            tokenSaleRound.duration = _durations[i];
            tokenSaleRound.minAmount = _minAmounts[i];
            tokenSaleRound.maxAmount = _maxAmounts[i];
            tokenSaleRound.purchasePrice = _purchasePrices[i];
            tokenSaleRound.tokensSold = 0;
            tokenSaleRound.totalPurchaseAmount = _purchaseAmounts[i];
            tokenSaleRound.isPublic = _isPublic[i];
            tokenSaleRound.isEnded = false;
        }
        roundsCounter = _purchaseAmounts.length - 1;
        usdtToken = _usdtToken;
        treasury = _treasury;
        swapRouter = IUniswapV2Router(_unirouter);
        path[0] = IUniswapV2Router(_unirouter).WETH();
        path[1] = _usdtToken;
    }

    receive() external payable {}

    modifier isEnded(uint256 roundId) {
        TokenSaleRound storage tokenSaleRound = rounds[roundId];
        require(!tokenSaleRound.isEnded, "TokenSale: Round is ended");
        _;
    }

    function buyForErc20(
        uint256 roundId,
        address token,
        uint256 amount
    ) external isEnded(roundId) {
        TokenSaleRound storage tokenSaleRound = rounds[roundId];

        if (!tokenSaleRound.isPublic) {
            require(whitelist[msg.sender], "TokenSale: not in whitelist");
        }

        require(isRoundStared(roundId), "TokenSale: Round is not started");
        require(
            amount >= tokenSaleRound.minAmount &&
                amount <= tokenSaleRound.maxAmount
        );

        uint256 tokenAmount = (amount / tokenSaleRound.purchasePrice) *
            PRECISSION;

        require(
            tokenSaleRound.tokensSold + tokenAmount <=
                tokenSaleRound.totalPurchaseAmount,
            "TokenSale not enough"
        );
        require(
            userSpentFunds[msg.sender][roundId] + amount <=
                tokenSaleRound.maxAmount,
            "TokenSale: You cannot purchase more maxAmount"
        );

        IERC20(token).safeTransferFrom(msg.sender, treasury, amount);
        tokenSaleRound.tokensSold += tokenAmount;
        userBalance[msg.sender][roundId] += tokenAmount;
        userSpentFunds[msg.sender][roundId] += amount;

        if (tokenSaleRound.tokensSold == tokenSaleRound.totalPurchaseAmount) {
            tokenSaleRound.isEnded = true;
        }
    }

    function buyForEth(uint256 roundId) external payable isEnded(roundId) {
        TokenSaleRound storage tokenSaleRound = rounds[roundId];

        if (!tokenSaleRound.isPublic) {
            require(whitelist[msg.sender], "TokenSale: not in whitelist");
        }

        require(isRoundStared(roundId), "TokenSale: Round is not started");

        // address[] memory path = new address[](2);
        // path[0] = swapRouter.WETH();
        // path[1] = usdtToken;
        uint256[] memory amounts = swapRouter.getAmountsOut(msg.value, path);

        require(
            amounts[1] >= tokenSaleRound.minAmount &&
                amounts[1] <= tokenSaleRound.maxAmount
        );

        (bool sent, ) = treasury.call{value: msg.value}("");
        require(sent, "Failed to send Ether");

        uint256 tokenAmount = (amounts[1] / tokenSaleRound.purchasePrice) *
            PRECISSION;

        require(
            tokenSaleRound.tokensSold + tokenAmount <=
                tokenSaleRound.totalPurchaseAmount,
            "TokenSale not enough"
        );

        require(
            userSpentFunds[msg.sender][roundId] + amounts[1] <=
                tokenSaleRound.maxAmount,
            "TokenSale: You cannot purchase more maxAmount"
        );

        tokenSaleRound.tokensSold += tokenAmount;
        userBalance[msg.sender][roundId] += tokenAmount;
        userSpentFunds[msg.sender][roundId] += amounts[1];

        if (tokenSaleRound.tokensSold == tokenSaleRound.totalPurchaseAmount) {
            tokenSaleRound.isEnded = true;
        }
    }

    function initTokenSale(uint256 roundId, uint256 startDate)
        external
        onlyOwner
    {
        require(roundId <= roundsCounter, "TokenSale: round not found");
        TokenSaleRound storage tokenSaleRound = rounds[roundId];
        require(!isRoundStared(roundId), "TokenSale: Round is started");

        tokenSaleRound.startTime = startDate;
        tokenSaleRound.endTime = startDate + tokenSaleRound.duration;
    }

    function endTokenSale(uint256 roundId) external onlyOwner {
        TokenSaleRound storage tokenSaleRound = rounds[roundId];
        tokenSaleRound.isEnded = true;
    }

    function updatePurchasePrice(uint256 roundId, uint256 newPurchasePrice)
        external
        onlyOwner
    {
        require(roundId <= roundsCounter, "TokenSale: round not found");
        require(!isRoundStared(roundId), "TokenSale: Round is started");
        require(
            newPurchasePrice > 0,
            "TokenSale: purchase prise must be more than zero"
        );
        TokenSaleRound storage tokenSaleRound = rounds[roundId];

        tokenSaleRound.purchasePrice = newPurchasePrice;
    }

    function updateRoundDuration(uint256 roundId, uint256 newDuration)
        external
        onlyOwner
    {
        require(roundId <= roundsCounter, "TokenSale: round not found");
        require(!isRoundStared(roundId), "TokenSale: Round is started");
        require(newDuration > 0, "TokenSale: Duration must be more than zero");
        TokenSaleRound storage tokenSaleRound = rounds[roundId];
        tokenSaleRound.duration = newDuration;
    }

    function updateMinMaxAmounts(
        uint256 roundId,
        uint256 min,
        uint256 max
    ) external onlyOwner {
        require(roundId <= roundsCounter, "TokenSale: round not found");
        require(!isRoundStared(roundId), "TokenSale: Round is started");
        require(max > min, "TokenSale: max must be more than min");
        require(max > 0 && min > 0, "TokenSale: must be grater than zero");
        TokenSaleRound storage tokenSaleRound = rounds[roundId];
        tokenSaleRound.maxAmount = max;
        tokenSaleRound.minAmount = min;
    }

    function addNewTokenSaleRound(
        uint256 purchaseAmount,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 duration,
        uint256 purchasePrice,
        bool isPublic
    ) external onlyOwner {
        require(
            purchaseAmount > 0 &&
                minAmount > 0 &&
                maxAmount > 0 &&
                duration > 0 &&
                purchasePrice > 0,
            "TokenSale: mast be grater than zero"
        );
        require(maxAmount > minAmount, "TokenSale: max must be more than min");
        roundsCounter++;
        TokenSaleRound storage tokenSaleRound = rounds[roundsCounter];
        tokenSaleRound.duration = duration;
        tokenSaleRound.isEnded = false;
        tokenSaleRound.isPublic = isPublic;
        tokenSaleRound.maxAmount = maxAmount;
        tokenSaleRound.minAmount = minAmount;
        tokenSaleRound.purchasePrice = purchasePrice;
        tokenSaleRound.totalPurchaseAmount = purchaseAmount;
        tokenSaleRound.tokensSold = 0;
    }

    function isRoundStared(uint256 roundId) public view returns (bool) {
        require(roundId <= roundsCounter, "TokenSale: round not found");
        TokenSaleRound storage tokenSaleRound = rounds[roundId];
        return (block.timestamp >= tokenSaleRound.startTime &&
            block.timestamp <= tokenSaleRound.endTime);
    }
}
