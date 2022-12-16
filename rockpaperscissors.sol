// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

contract RockPaperScissors {
    enum Moves {
        None,
        Rock,
        Paper,
        Scissors
    }
    enum Outcomes {
        None,
        PlayerA,
        PlayerB,
        Draw
    } // Possible Outcomes

    uint256 public constant BET_MIN = 1 gwei; // The minimum bet
    uint256 public constant REVEAL_TIMEOUT = 10 minutes; // Max delay of revelation phase
    uint256 public initialBet; // Bet of first player
    uint256 private _firstReveal; // Moment of first reveal

    // Players' addresses
    address public playerA;
    address public playerB;

    // Encrypted moves
    bytes32 private _encrMovePlayerA;
    bytes32 private _encrMovePlayerB;

    // Clear moves set only after both players have committed their encrypted moves
    Moves private _movePlayerA;
    Moves private _movePlayerB;

    /**************************************************************************/
    /*************************** REGISTRATION PHASE ***************************/
    /**************************************************************************/

    // Bet must be greater than a minimum amount and greater than bet of first player
    modifier validBet() {
        require(msg.value >= BET_MIN);
        require(initialBet == 0 || msg.value >= initialBet);
        _;
    }

    modifier notAlreadyRegistered() {
        require(msg.sender != playerA && msg.sender != playerB);
        _;
    }

    // Register a player.
    // Return player's ID upon successful registration.
    function register()
        public
        payable
        validBet
        notAlreadyRegistered
        returns (uint256)
    {
        if (playerA == address(0)) {
            playerA = msg.sender;
            initialBet = msg.value;
            return 1;
        } else if (playerB == address(0)) {
            playerB = msg.sender;
            return 2;
        }
        return 0;
    }

    /**************************************************************************/
    /****************************** COMMIT PHASE ******************************/
    /**************************************************************************/

    modifier isRegistered() {
        require(msg.sender == playerA || msg.sender == playerB);
        _;
    }

    // Save player's encrypted move.
    // Return 'true' if move was valid, 'false' otherwise.
    function play(bytes32 encrMove) public isRegistered returns (bool) {
        if (msg.sender == playerA && _encrMovePlayerA == 0) {
            _encrMovePlayerA = encrMove;
        } else if (msg.sender == playerB && _encrMovePlayerB == 0) {
            _encrMovePlayerB = encrMove;
        } else {
            return false;
        }
        return true;
    }

    /**************************************************************************/
    /****************************** REVEAL PHASE ******************************/
    /**************************************************************************/

    modifier commitPhaseEnded() {
        require(_encrMovePlayerA != 0 && _encrMovePlayerB != 0);
        _;
    }

    // Compare clear move given by the player with saved encrypted move.
    // Return clear move upon success, 'Moves.None' otherwise.
    function reveal(string memory clearMove)
        public
        isRegistered
        commitPhaseEnded
        returns (Moves)
    {
        bytes32 encrMove = sha256(abi.encodePacked(clearMove)); // Hash of clear input (= "move-password")
        Moves move = Moves(_getFirstChar(clearMove)); // Actual move (Rock / Paper / Scissors)

        // If move invalid, exit
        if (move == Moves.None) {
            return Moves.None;
        }

        // If hashes match, clear move is saved
        if (msg.sender == playerA && encrMove == _encrMovePlayerA) {
            _movePlayerA = move;
        } else if (msg.sender == playerB && encrMove == _encrMovePlayerB) {
            _movePlayerB = move;
        } else {
            return Moves.None;
        }

        // Timer starts after first revelation from one of the player
        if (_firstReveal == 0) {
            _firstReveal = block.timestamp;
        }

        return move;
    }

    // Return first character of a given string.
    function _getFirstChar(string memory str) private pure returns (uint256) {
        bytes1 firstByte = bytes(str)[0];
        if (firstByte == 0x31) {
            return 1;
        } else if (firstByte == 0x32) {
            return 2;
        } else if (firstByte == 0x33) {
            return 3;
        } else {
            return 0;
        }
    }

    /**************************************************************************/
    /****************************** RESULT PHASE ******************************/
    /**************************************************************************/

    modifier revealPhaseEnded() {
        require(
            (_movePlayerA != Moves.None && _movePlayerB != Moves.None) ||
                (_firstReveal != 0 &&
                    block.timestamp > _firstReveal + REVEAL_TIMEOUT)
        );
        _;
    }

    // Compute the outcome and pay the winner(s).
    // Return the outcome.
    function getOutcome() public revealPhaseEnded returns (Outcomes) {
        Outcomes outcome;

        if (_movePlayerA == _movePlayerB) {
            outcome = Outcomes.Draw;
        } else if (
            (_movePlayerA == Moves.Rock && _movePlayerB == Moves.Scissors) ||
            (_movePlayerA == Moves.Paper && _movePlayerB == Moves.Rock) ||
            (_movePlayerA == Moves.Scissors && _movePlayerB == Moves.Paper) ||
            (_movePlayerA != Moves.None && _movePlayerB == Moves.None)
        ) {
            outcome = Outcomes.PlayerA;
        } else {
            outcome = Outcomes.PlayerB;
        }

        uint256 betPlayerA = initialBet;
        _reset(); // Reset game before paying to avoid reentrancy attacks
        _pay(payable(playerA), payable(playerB), betPlayerA, outcome);

        return outcome;
    }

    // Pay the winner(s).
    function _pay(
        address payable addrA,
        address payable addrB,
        uint256 betPlayerA,
        Outcomes outcome
    ) private {
        // Uncomment lines below if you need to adjust the gas limit
        if (outcome == Outcomes.PlayerA) {
            addrA.transfer(address(this).balance);
            // addrA.call.value(address(this).balance).gas(1000000)("");
        } else if (outcome == Outcomes.PlayerB) {
            addrB.transfer(address(this).balance);
            // addrB.call.value(address(this).balance).gas(1000000)("");
        } else {
            addrA.transfer(betPlayerA);
            addrB.transfer(address(this).balance);
            // addrA.call.value(betPlayerA).gas(1000000)("");
            // addrB.call.value(address(this).balance).gas(1000000)("");
        }
    }

    // Reset the game.
    function _reset() private {
        initialBet = 0;
        _firstReveal = 0;
        playerA = address(0);
        playerB = address(0);
        _encrMovePlayerA = 0;
        _encrMovePlayerB = 0;
        _movePlayerA = Moves.None;
        _movePlayerB = Moves.None;
    }

    /**************************************************************************/
    /**************************** HELPER FUNCTIONS ****************************/
    /**************************************************************************/

    // Return contract balance
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // Return player's ID
    function whoAmI() public view returns (uint256) {
        if (msg.sender == playerA) {
            return 1;
        } else if (msg.sender == playerB) {
            return 2;
        } else {
            return 0;
        }
    }

    // Return 'true' if both players have commited a move, 'false' otherwise.
    function bothPlayed() public view returns (bool) {
        return (_encrMovePlayerA != 0 && _encrMovePlayerB != 0);
    }

    // Return 'true' if both players have revealed their move, 'false' otherwise.
    function bothRevealed() public view returns (bool) {
        return (_movePlayerA != Moves.None && _movePlayerB != Moves.None);
    }

    // Return time left before the end of the revelation phase.
    function revealTimeLeft() public view returns (int256) {
        if (_firstReveal != 0) {
            return int256((_firstReveal + REVEAL_TIMEOUT) - block.timestamp);
        }
        return int256(REVEAL_TIMEOUT);
    }
}
