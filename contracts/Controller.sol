// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./AiAgentToken.sol";
import "./BondingCurve.sol";
contract Controller is Ownable {
    mapping(address => address) private _tokens;
    mapping(address => address) private _bondings;
    uint256 public FEE = 0.1 ether;
    address public FEE_RECEIVER;
    uint256 private MAX_CREATOR_BUY_PERCENT = 500; // 5%;
    uint256 public constant BONDING_PERCENT = 7000;
    uint256 public constant DENOMINATOR = 10000;

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
        uint256 bondingSupply = (totalSupply * BONDING_PERCENT) / DENOMINATOR;
        BondingCurve newBondingCurve = new BondingCurve(
            address(agentToken),
            address(this),
            bondingSupply
        );
        _tokens[msg.sender] = address(agentToken);
        _bondings[address(agentToken)] = address(newBondingCurve);

        //  auto buy when use create and send token >fee
        uint256 buyAmount = msg.value - FEE;
        if (buyAmount > 0) {
            uint256 tokenAmount = newBondingCurve.getTokensForETH(buyAmount);
            console.log("tokenAmount", tokenAmount);
            uint256 maxBuy = (totalSupply * MAX_CREATOR_BUY_PERCENT) /
                DENOMINATOR;
            if (tokenAmount > maxBuy) {
                tokenAmount = maxBuy;
            }
            newBondingCurve.creatorBuyEvent(msg.sender, buyAmount, tokenAmount);
            agentToken.createVestingScheduleForCreator(msg.sender, tokenAmount);
            payable(address(newBondingCurve)).transfer(buyAmount);
        }

        uint256 liquidityAmount = (totalSupply *
            agentToken.LIQUIDITY_PERCENT()) / 100;
        agentToken.mint(address(newBondingCurve), liquidityAmount);
        agentToken.setAdmin(address(newBondingCurve), true);

        emit TokenCreated(
            address(agentToken),
            name,
            symbol,
            msg.sender,
            totalSupply
        );
        emit BondingCurveCreated(address(newBondingCurve), address(agentToken));

        return address(agentToken);
    }

    function _payFee() private {
        require(msg.value >= FEE, "invalid value!");
        payable(address(FEE_RECEIVER)).transfer(FEE);
    }

    function setFee(uint256 newFee) public onlyOwner {
        FEE = newFee;
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

    //TODO
    // recheck admin func
    // refactor code
}
