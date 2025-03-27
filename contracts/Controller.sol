// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./AiAgentToken.sol";
import "./BondingCurve.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract Controller is Ownable {
    struct BondingData {
        address bondingAddr;
        address tokenAdddr;
    }
    //REMOVE LATER
    mapping(address => address) private _tokens;
    mapping(address => address) private _bondings;
    uint256 public FEE = 0.001 ether;
    address public FEE_RECEIVER;
    uint256 private MAX_CREATOR_BUY_PERCENT = 500; // 5%;
    uint256 public constant BONDING_PERCENT = 7500;
    uint256 public constant DENOMINATOR = 10000;
    BondingData[] private _bondingList; //REMOVE LATER
    address public FEE_TOKEN_ADDRESS =
        0xB45D900cc0F65A42f16d4c756319DCac9E71a0cc;
    uint256 public TOKEN_FEE = 50 ether; // Default 50 tokens with 18 decimals

    event TokenCreated(
        address indexed tokenAddress,
        string name,
        string symbol,
        address owner,
        uint256 totalSupply
    );

    event BondingCurveCreated(
        address indexed bondingAddress,
        address indexed tokenAddress
    );

    constructor(address receiver) Ownable(msg.sender) {
        FEE_RECEIVER = receiver;
    }
    function createToken(
        string memory name,
        string memory symbol,
        address stakingWallet,
        uint256 totalSupply
    ) public payable returns (address) {
        _payFee();
        AiAgentToken agentToken = new AiAgentToken(
            name,
            symbol,
            address(this),
            stakingWallet,
            msg.sender,
            totalSupply
        );

        address agentAddr = address(agentToken);
        uint256 bondingSupply = (totalSupply * BONDING_PERCENT) / DENOMINATOR;
        BondingCurve newBondingCurve = new BondingCurve(
            agentAddr,
            address(this),
            bondingSupply
        );
        address bondingAddr = address(newBondingCurve);
        _tokens[msg.sender] = agentAddr;
        _bondings[agentAddr] = bondingAddr;

        //  auto buy when use create and send token >fee
        if (msg.value > FEE) {
            uint256 buyAmount = msg.value - FEE;
            _buy(bondingAddr, agentAddr, bondingSupply, buyAmount);
        }

        _transferLiquid(totalSupply, agentAddr, bondingAddr);
        emit TokenCreated(agentAddr, name, symbol, msg.sender, totalSupply);
        emit BondingCurveCreated(bondingAddr, agentAddr);

        _bondingList.push(BondingData(bondingAddr, agentAddr));
        return agentAddr;
    }

    function _buy(
        address bondingAddr,
        address tokenAddr,
        uint256 bondingSupply,
        uint256 buyAmount
    ) private {
        BondingCurve bondingCurve = BondingCurve(payable(bondingAddr));
        uint256 tokenAmount = bondingCurve.getTokensForETH(buyAmount);
        uint256 maxBuy = (bondingSupply * MAX_CREATOR_BUY_PERCENT) /
            DENOMINATOR;
        if (tokenAmount > maxBuy) {
            tokenAmount = maxBuy;
        }
        bondingCurve.creatorBuy(msg.sender, buyAmount, tokenAmount);
        AiAgentToken(tokenAddr).createVestingScheduleForCreator(
            msg.sender,
            tokenAmount
        );
        payable(bondingAddr).transfer(buyAmount);
    }

    function _transferLiquid(
        uint256 totalSupply,
        address agentAddr,
        address bondingAddr
    ) private {
        AiAgentToken agentToken = AiAgentToken(agentAddr);
        uint256 liquidityAmount = (totalSupply *
            agentToken.LIQUIDITY_PERCENT()) / 100;
        agentToken.mint(bondingAddr, liquidityAmount);
        agentToken.setAdmin(bondingAddr, true);
    }

    function _payFee() private {
        if (msg.value > 0) {
            require(msg.value >= FEE, "Insufficient balance!");
            payable(address(FEE_RECEIVER)).transfer(FEE);
        } else {
            IERC20 token = IERC20(FEE_TOKEN_ADDRESS);
            token.transferFrom(msg.sender, address(FEE_RECEIVER), TOKEN_FEE);
        }
    }

    function setFee(uint256 newFee) public onlyOwner {
        FEE = newFee;
    }

    function setTokenFee(uint256 newFee) public onlyOwner {
        TOKEN_FEE = newFee;
    }

    function setFeeReceiver(address _address) public onlyOwner {
        require(_address != address(0), "Invalid address!");
        FEE_RECEIVER = _address;
    }

    function setTokenFeeAddress(address _address) public onlyOwner {
        require(_address != address(0), "Invalid address!");
        FEE_TOKEN_ADDRESS = _address;
    }

    function transferAdmin(address newAdmin) public onlyOwner {
        transferOwnership(newAdmin);
    }
    function getTokenByOwner(address owner) public view returns (address) {
        //TODO: REMOVE later, use for dev contract test.
        return _tokens[owner];
    }

    function getBondingByToken(address token) public view returns (address) {
        return _bondings[token];
    }

    function getBondingList() public view returns (BondingData[] memory) {
        return _bondingList;
    }

    //TODO
    // add staking contract
    // recheck admin func
    // refactor code
}
