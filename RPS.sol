
// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./CommitReveal.sol";
import "./TimeUnit.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract RPS is CommitReveal, TimeUnit{
    uint public numPlayer = 0;
    uint public reward = 0;
    mapping (address => uint) public player_choice;
    mapping(address => bool) public player_played;
    mapping(address => bool) public player_not_revealed;
    address[] public players;
    uint public numInput = 0;
    uint public numPlayerReveal = 0;
    IERC20 public token;
    uint256 public constant BET_AMOUNT = 0.000001 ether;

    event GameReset();
    event Approved(address indexed player, uint256 amount);
    event Deposited(address indexed player, uint256 amount);

    constructor(address _token) {
        token = IERC20(_token);
    }
    
    function addPlayer() public payable {
        require(numPlayer < 2);
        if (numPlayer > 0) {
            require(msg.sender != players[0]);
        }
        require(token.allowance(msg.sender, address(this)) >= BET_AMOUNT, "Insufficient allowance");

        players.push(msg.sender);
        player_played[msg.sender] = true;
        numPlayer++;

        if (numPlayer == 2) {
            startTime = block.timestamp;
        }
    }

    function approve() public {
        require(player_played[msg.sender]);
        token.approve(address(this), BET_AMOUNT);
        emit Approved(msg.sender, BET_AMOUNT);
    }

    function _collectBets() private {
        for (uint i = 0; i < players.length; i++) {
            require(token.transferFrom(players[i], address(this), BET_AMOUNT), "Transfer failed");
            reward += BET_AMOUNT;
            emit Deposited(players[i], BET_AMOUNT);
        }
    }

    function getChoiceHash(uint256 choice, string memory salt) public pure returns (bytes32) {
        require(choice >= 0 && choice <= 2, "Invalid choice"); // 0-2 for RPS

        bytes32 _salt = keccak256(abi.encodePacked(salt)); 
        bytes32 _choice = bytes32(choice); 

        return getHash(keccak256(abi.encodePacked(_choice, _salt))); 
    }

    function commitChoice(bytes32 commitHash) public {
        require(numPlayer == 2);
        require(player_played[msg.sender]);

        player_not_revealed[msg.sender] = true;
        numInput++;

        commit(commitHash);
        if (numInput == 2 ) {
            _collectBets();
        }
    }

    function revealChoice(uint choice, string memory salt) public {
        require(numPlayer == 2);
        require(numInput == 2);
        require(player_played[msg.sender]);
        require(choice >= 0 && choice <= 2, "Invalid choice"); // 0-2 for RPS
        
        bytes32 _salt = keccak256(abi.encodePacked(salt)); 
        bytes32 _choice = bytes32(choice); 
        bytes32 revealHash = keccak256(abi.encodePacked(_choice, _salt));
        reveal(revealHash);
        
        player_choice[msg.sender] = choice;
        player_played[msg.sender] = false;
        player_not_revealed[msg.sender] = false;
        numPlayerReveal++;
        
        if (numPlayerReveal == 2) {
            _checkWinnerAndPay();
        }
    }

    function refundNotRevealCase() public {
        require(numInput == 2);
        require(numPlayerReveal < 2);
        require(elapsedMinutes() >= 20 minutes);
        
        address payable account0 = payable(players[0]);
        address payable account1 = payable(players[1]);

        if (player_not_revealed[players[0]]) {
            account1.transfer(reward);
        } else {
            account0.transfer(reward);
        }
        
        _resetGame();
    }

    function refundNoPlayerReveal() public {
        require(numInput == 2);
        require(numPlayerReveal == 0);
        require(elapsedMinutes() >= 20 minutes);

        address payable refunder = payable(msg.sender);
        refunder.transfer(reward);

        _resetGame();
    }


    function _resetGame() public {
        for(uint i = 0; i < players.length; i++) {
            player_played[players[i]] = false;
            player_choice[players[i]] = 3; // Reset to undefined
            player_not_revealed[players[i]] = true;
        }
        players = new address[](0);
        numPlayer = 0;
        numInput = 0;
        numPlayerReveal = 0;
        reward = 0;
        startTime = 0;
        
        emit GameReset();
    }

    function _checkWinnerAndPay() private {
        uint p0Choice = player_choice[players[0]];
        uint p1Choice = player_choice[players[1]];
        address payable account0 = payable(players[0]);
        address payable account1 = payable(players[1]);
        if ((p0Choice + 1) % 3 == p1Choice) {
            // to pay player[1]
            account1.transfer(reward);
        }
        else if ((p1Choice + 1) % 3 == p0Choice) {
            // to pay player[0]
            account0.transfer(reward);    
        }
        else {
            // to split reward
            account0.transfer(reward / 2);
            account1.transfer(reward / 2);
        }
    }
}
