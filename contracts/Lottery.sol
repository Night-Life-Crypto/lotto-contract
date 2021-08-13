pragma solidity ^0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

contract Lottery is Context, Ownable, VRFConsumerBase {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;
    enum LOTTERY_STATE {
        OPEN,
        CLOSED,
        CALCULATING_WINNER
    }
    LOTTERY_STATE public lotteryState;

    address public NLIFE;
    address public feeWallet;

    bytes32 internal keyHash;
    uint256 public fee;

    uint256 public lotteryId;
    uint8 public randomNumberId;
    mapping(bytes32 => uint256) public requestIds;
    uint256 public randomResult;
    uint256[] public randomNumber;

    address[] public players;

    uint256 public winnerNumber1;
    uint256 public winnerNumber2;
    uint256 public winnerNumber3;
    address[] public firstWinners;
    address[] public secondWinners;
    uint8 public winnerType;

    mapping(address => uint256) public tickets;
    uint256 public ticketPrice;

    struct LotteryValue {
        address player;
        uint64 number1;
        uint64 number2;
        uint64 number3;
    }

    LotteryValue[] public _lotteryValue;

    event BUY_TICKET(address buyer, uint256 amount);
    event ENTER_LOTTERY(
        address player,
        uint64 number1,
        uint64 number2,
        uint64 number3
    );
    event LOTTERY_WINNERS(
        address[] firstWinners,
        address[] secondWinners,
        uint256 jackpot,
        uint256 runnerup
    );

    /**
     * Constructor inherits VRFConsumerBase
     *
     * Network: Kovan
     * Chainlink VRF Coordinator address: 0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9
     * LINK token address:                0xa36085F69e2889c224210F603D836748e7dC0088
     * Key Hash: 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4
     */
    constructor(
        address _vrfCoordinator,
        address _link,
        bytes32 _keyHash,
        address _NLIFE
    )
        public
        VRFConsumerBase(
            _vrfCoordinator, // VRF Coordinator
            _link // LINK Token
        )
    {
        NLIFE = _NLIFE;

        keyHash = _keyHash;
        fee = 0.1 * 10**18;

        lotteryId = 1;
        randomNumberId = 1;

        ticketPrice = 10**18; // ticket price : 1 NLIFE
        lotteryState = LOTTERY_STATE.CLOSED;
    }

    /**
     * Requests randomness from a user-provided seed
     */
    function getRandomNumber() public {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );
        bytes32 _requestId = requestRandomness(keyHash, fee);
        requestIds[_requestId] = lotteryId;
        lotteryId = lotteryId + 1;
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResult = randomness;
        if (randomNumberId == 1) {
            winnerNumber1 = randomness % 26;
        } else if (randomNumberId == 2) {
            winnerNumber2 = randomness % 26;
        } else if (randomNumberId == 3) {
            winnerNumber3 = randomness % 26;
        }
        randomNumberId++;
        lotteryId = requestIds[requestId];
        randomNumber.push(randomness);
    }

    /**
     * Withdraw LINK from this contract
     *
     * DO NOT USE THIS IN PRODUCTION AS IT CAN BE CALLED BY ANY ADDRESS.
     * THIS IS PURELY FOR EXAMPLE PURPOSES.
     */
    function withdrawLink() external onlyOwner {
        require(
            LINK.transfer(msg.sender, LINK.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    /**
     * Update lottery token
     */
    function updateToken(address _NLIFE) external onlyOwner {
        NLIFE = _NLIFE;
    }

    /**
     * Update fee wallet address
     */
    function updateFeeWallet(address _feeWallet) external onlyOwner {
        feeWallet = _feeWallet;
    }

    /**
     * Set price for ticket
     */
    function setTicketPrice(uint256 _price) external onlyOwner {
        ticketPrice = _price;
    }

    /**
     * buy tickets with NLIFE token
     */
    function buyTicket(uint256 _amount) public {
        uint256 allowance = IERC20(NLIFE).allowance(msg.sender, address(this));
        require(
            allowance >= _amount * ticketPrice,
            "Check the token allowance"
        );
        uint256 _fee = (_amount * ticketPrice * 76923) / 1000000;
        IERC20(NLIFE).transferFrom(
            msg.sender,
            address(this),
            _amount * ticketPrice
        );
        IERC20(NLIFE).transfer(feeWallet, _fee);
        tickets[msg.sender] = tickets[msg.sender] + _amount;
        BUY_TICKET(msg.sender, _amount);
    }

    /**
     * check ticket balance
     */
    function viewTicketBalance() public view returns (uint256 amount) {
        return tickets[msg.sender];
    }

    /**
     * enter lottery
     */
    function enter(
        uint64 _number1,
        uint64 _number2,
        uint64 _number3
    ) public {
        require(
            lotteryState == LOTTERY_STATE.OPEN,
            "New lotter is not started."
        );
        require(tickets[msg.sender] >= 1, "You don't have any tickets.");
        require(
            _number1 >= 0 && _number1 < 26,
            "Lottery Number should be between 0 and 25."
        );
        require(
            _number2 >= 0 && _number2 < 26,
            "Lottery Number should be between 0 and 25."
        );
        require(
            _number3 >= 0 && _number3 < 26,
            "Lottery Number should be between 0 and 25."
        );

        tickets[msg.sender] = tickets[msg.sender] - 1;
        players.push(msg.sender);
        _lotteryValue.push(
            LotteryValue(msg.sender, _number1, _number2, _number3)
        );

        ENTER_LOTTERY(msg.sender, _number1, _number2, _number3);
    }

    function startNewLottery() public onlyOwner {
        require(
            lotteryState == LOTTERY_STATE.CLOSED,
            "can't start a new lottery yet"
        );
        lotteryState = LOTTERY_STATE.OPEN;
    }

    function endLottery() public onlyOwner {
        require(
            lotteryState == LOTTERY_STATE.OPEN,
            "The lottery hasn't even started!"
        );
        // add a require here so that only the oracle contract can
        // call the fulfill alarm method
        lotteryState = LOTTERY_STATE.CALCULATING_WINNER;
        lotteryId = lotteryId + 1;
    }

    function pickWinner() public {
        require(
            lotteryState == LOTTERY_STATE.CALCULATING_WINNER,
            "You aren't at that stage yet!"
        );

        uint256 jackPotAmount = IERC20(NLIFE).balanceOf(address(this));

        getRandomNumber();
        getRandomNumber();
        getRandomNumber();

        for (uint256 i = 0; i < players.length; i++) {
            winnerType = 0;
            if (_lotteryValue[i].number1 == winnerNumber1) {
                winnerType++;
            }
            if (_lotteryValue[i].number2 == winnerNumber2) {
                winnerType++;
            }
            if (_lotteryValue[i].number3 == winnerNumber3) {
                winnerType++;
            }
            if (winnerType == 2) {
                secondWinners.push(_lotteryValue[i].player);
            } else if (winnerType == 3) {
                firstWinners.push(_lotteryValue[i].player);
            }
        }

        uint256 firstAmount = 0;
        uint256 secondAmount = 0;
        if (secondWinners.length > 0) {
            secondAmount = (jackPotAmount * 20) / 100;
            sendFunds(secondWinners, secondAmount / secondWinners.length);

            if (firstWinners.length > 0) {
                firstAmount = jackPotAmount - secondAmount;
                sendFunds(firstWinners, firstAmount / firstWinners.length);
            }
        } else if (firstWinners.length > 0) {
            firstAmount = jackPotAmount / firstWinners.length;
            sendFunds(firstWinners, firstAmount);
        }

        emit LOTTERY_WINNERS(
            firstWinners,
            secondWinners,
            firstAmount,
            secondAmount
        );

        for (uint256 i = 0; i < players.length; i++) {
            delete _lotteryValue[i];
        }
        players = new address[](0);
        firstWinners = new address[](0);
        secondWinners = new address[](0);
        lotteryState = LOTTERY_STATE.CLOSED;
        //this kicks off the request and returns through fulfill_random
    }

    function sendFunds(address[] memory receivers, uint256 amount) internal {
        for (uint256 i = 0; i < receivers.length; i++) {
            // LINK.transferFrom(address(this), receivers[i], amount);
            IERC20(NLIFE).transfer(receivers[i], amount);
        }
    }

    function getPlayers() public view returns (address[] memory) {
        return players;
    }
}
