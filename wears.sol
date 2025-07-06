// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PhraseOwnershipHashedInternal {
    enum PhraseStatus {
        Created,
        ConfirmationAwaiting,
        Confirmed
    }

    struct PhraseInfo {
        address owner;
        string message;
        PhraseStatus status;
        uint confirmationDelaySeconds;
        uint confirmationPeriodSeconds;
    }

    mapping(bytes32 => PhraseInfo) private phrases;
    mapping(bytes32 => uint256) private confirmationStartedAt;

    address public admin;

    uint constant MAX_MESSAGE_LENGTH = 256;

    // --- Events ---
    event PhraseAdded(
        bytes32 indexed phraseHash,
        address owner,
        string message,
        PhraseStatus status
    );
    event ConfirmationStarted(bytes32 indexed phraseHash, address owner);
    event OwnershipConfirmed(bytes32 indexed phraseHash, address confirmedOwner);
    event OwnershipTransferred(
        bytes32 indexed phraseHash,
        address oldOwner,
        address newOwner
    );
    event MessageUpdated(bytes32 indexed phraseHash, string newOwnerInfo);
    event PhraseRevertedToAdmin(bytes32 indexed phraseHash);
    event PhraseDeleted(bytes32 indexed phraseHash, address by);
    event AdminChanged(address oldAdmin, address newAdmin);

    // --- Modifiers ---
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call");
        _;
    }

    modifier onlyOwner(bytes32 phraseHash) {
        require(phrases[phraseHash].owner == msg.sender, "Only owner can call");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    // --- Public / External Functions ---

    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "New admin cannot be zero address");
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }

    function addPhrase(string calldata phrase, string calldata message) external onlyAdmin {
        require(bytes(phrase).length > 0, "Phrase is empty");
        require(bytes(message).length <= MAX_MESSAGE_LENGTH, "Message info too long");

        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        require(phrases[phraseHash].owner == address(0), "Phrase already exists");

        phrases[phraseHash] = PhraseInfo({
            owner: admin,
            message: string(message),
            status: PhraseStatus.Created,
            confirmationDelaySeconds: 0,
            confirmationPeriodSeconds: 0
        });

        emit PhraseAdded(phraseHash, admin, message, PhraseStatus.Created);
    }

    function startConfirmation(string calldata phrase) external {
        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        PhraseInfo storage info = phrases[phraseHash];

        require(info.status == PhraseStatus.Created, "Not in Created status");
        require(info.owner == msg.sender, "Only declared owner can start confirmation");
        require(info.confirmationDelaySeconds > 0 && info.confirmationPeriodSeconds > 0, "Confirmation settings not set");

        info.status = PhraseStatus.ConfirmationAwaiting;
        confirmationStartedAt[phraseHash] = block.timestamp;

        emit ConfirmationStarted(phraseHash, msg.sender);
    }

    function confirm(string calldata phrase) external {
        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        PhraseInfo storage info = phrases[phraseHash];

        require(info.status == PhraseStatus.ConfirmationAwaiting, "Not in confirmation stage");
        require(info.owner == msg.sender, "Only owner can confirm");

        uint256 startedAt = confirmationStartedAt[phraseHash];
        require(startedAt > 0, "Confirmation not started");

        uint256 delayEnd = startedAt + info.confirmationDelaySeconds;
        uint256 periodEnd = delayEnd + info.confirmationPeriodSeconds;

        require(block.timestamp >= delayEnd, "Confirmation delay not passed");
        require(block.timestamp <= periodEnd, "Confirmation period expired");

        info.status = PhraseStatus.Confirmed;

        info.confirmationDelaySeconds = 0;
        info.confirmationPeriodSeconds = 0;
        delete confirmationStartedAt[phraseHash];

        emit OwnershipConfirmed(phraseHash, msg.sender);
    }

    function revertToAdminIfExpiredBatch(string[] calldata phraseList) external {
        for (uint i = 0; i < phraseList.length; i++) {
            bytes32 phraseHash = keccak256(abi.encodePacked(phraseList[i]));
            PhraseInfo storage info = phrases[phraseHash];

            if (
                info.status == PhraseStatus.ConfirmationAwaiting &&
                confirmationStartedAt[phraseHash] > 0
            ) {
                uint256 startedAt = confirmationStartedAt[phraseHash];
                uint256 expirationTime = startedAt + info.confirmationDelaySeconds + info.confirmationPeriodSeconds;

                if (block.timestamp > expirationTime) {
                    address oldOwner = info.owner;

                    info.owner = admin;
                    info.message = "";
                    info.status = PhraseStatus.Created;

                    info.confirmationDelaySeconds = 0;
                    info.confirmationPeriodSeconds = 0;
                    delete confirmationStartedAt[phraseHash];

                    emit PhraseRevertedToAdmin(phraseHash);
                    emit OwnershipTransferred(phraseHash, oldOwner, admin);
                }
            }
        }
    }

    function transferOwnershipImmediately(string calldata phrase, address newOwner) external {
        require(newOwner != address(0), "New owner cannot be zero address");

        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        PhraseInfo storage info = phrases[phraseHash];

        require(info.owner == msg.sender, "Only current owner can transfer ownership");

        address oldOwner = info.owner;
        info.owner = newOwner;

        emit OwnershipTransferred(phraseHash, oldOwner, newOwner);
    }

    function updateMessage(string calldata phrase, string calldata message) external {
        require(bytes(message).length <= MAX_MESSAGE_LENGTH, "Message too long");

        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        PhraseInfo storage info = phrases[phraseHash];

        require(info.owner == msg.sender, "Only owner can update message");

        info.message = string(message);

        emit MessageUpdated(phraseHash, message);
    }

    function transferOwnershipByAdmin(
        string calldata phrase,
        address newOwner,
        uint confirmationDelaySeconds,
        uint confirmationPeriodSeconds
    ) external onlyAdmin {
        require(newOwner != address(0), "New owner cannot be zero address");
        require(confirmationDelaySeconds > 0, "Delay must be > 0");
        require(confirmationPeriodSeconds > 0, "Period must be > 0");

        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        PhraseInfo storage info = phrases[phraseHash];

        address oldOwner = info.owner;
        info.owner = newOwner;
        info.status = PhraseStatus.Created;
        info.confirmationDelaySeconds = confirmationDelaySeconds;
        info.confirmationPeriodSeconds = confirmationPeriodSeconds;

        emit OwnershipTransferred(phraseHash, oldOwner, newOwner);
    }

    function deletePhraseByOwner(string calldata phrase) external onlyAdmin {
        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        PhraseInfo storage info = phrases[phraseHash];

        require(info.owner == admin, "Phrase owner is not admin");

        delete phrases[phraseHash];
        delete confirmationStartedAt[phraseHash];

        emit PhraseDeleted(phraseHash, msg.sender);
    }

    function getPhraseInfo(string calldata phrase) external view returns (
        address owner,
        string memory message,
        PhraseStatus status,
        uint confirmationDelaySeconds,
        uint confirmationPeriodSeconds,
        uint confirmationStartedTimestamp
    ) {
        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        PhraseInfo memory info = phrases[phraseHash];
        uint startedAt = confirmationStartedAt[phraseHash];
        return (
            info.owner,
            info.message,
            info.status,
            info.confirmationDelaySeconds,
            info.confirmationPeriodSeconds,
            startedAt
        );
    }

    function getConfirmationAvailableAt(string calldata phrase) external view returns (uint256) {
        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        return confirmationStartedAt[phraseHash] + phrases[phraseHash].confirmationDelaySeconds;
    }

    function phraseExists(string calldata phrase) external view returns (bool) {
        bytes32 phraseHash = keccak256(abi.encodePacked(phrase));
        return phrases[phraseHash].owner != address(0);
    }
}
