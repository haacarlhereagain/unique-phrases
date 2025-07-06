// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PhrasesOwnershipHashed {
    enum PhraseStatus {
        Created,
        ConfirmationAwaiting,
        Confirmed
    }

    struct PhraseInfo {
        address owner;
        bytes32 claimHash;
        PhraseStatus status;
        uint confirmationDelaySeconds;
        uint confirmationPeriodSeconds;
        bool exists;
    }

    mapping(bytes32 => PhraseInfo) private phrases;
    mapping(bytes32 => uint256) private confirmationStartedAt;

    address public admin;

    // --- Events ---
    event PhraseAdded(bytes32 indexed phraseHash, address owner, PhraseStatus status);
    event OwnershipConfirmed(bytes32 indexed phraseHash, address confirmedOwner);
    event OwnershipTransferred(bytes32 indexed phraseHash, address oldOwner, address newOwner);
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

    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "New admin cannot be zero address");
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }

    function createPhrase(
        bytes32 phraseHash,
        bytes32 claimHash,
        uint confirmationDelaySeconds,
        uint confirmationPeriodSeconds
    ) external onlyAdmin {
        require(phraseHash != bytes32(0), "Invalid phrase hash");
        require(!phraseExists(phraseHash), "Phrase already exists");

        phrases[phraseHash] = PhraseInfo({
            owner: admin,
            status: PhraseStatus.Created,
            confirmationDelaySeconds: confirmationDelaySeconds,
            confirmationPeriodSeconds: confirmationPeriodSeconds,
            claimHash: claimHash,
            exists: true
        });

        emit PhraseAdded(phraseHash, admin, PhraseStatus.Created);
    }

    function confirm(bytes32 phraseHash, address newOwner) external onlyAdmin {
        require(phraseExists(phraseHash), "Phrase does not exist");

        PhraseInfo storage info = phrases[phraseHash];

        require(info.status == PhraseStatus.ConfirmationAwaiting, "Not in awaiting confirmation stage");


        uint256 startedAt = confirmationStartedAt[phraseHash];
        require(startedAt > 0, "Confirmation not started");

        uint256 delayEnd = startedAt + info.confirmationDelaySeconds;
        uint256 periodEnd = delayEnd + info.confirmationPeriodSeconds;

        require(block.timestamp >= delayEnd, "Confirmation delay not passed");
        require(block.timestamp <= periodEnd, "Confirmation period expired");

        info.status = PhraseStatus.Confirmed;
        info.confirmationDelaySeconds = 0;
        info.confirmationPeriodSeconds = 0;
        info.owner = newOwner;
        info.claimHash = 0;
        delete confirmationStartedAt[phraseHash];

        emit OwnershipConfirmed(phraseHash, newOwner);
    }

    function revertToAdminIfExpiredBatch(bytes32[] calldata phraseHashes) external onlyAdmin {
        for (uint i = 0; i < phraseHashes.length; i++) {
            bytes32 phraseHash = phraseHashes[i];
            PhraseInfo storage info = phrases[phraseHash];

            if (info.status == PhraseStatus.ConfirmationAwaiting && confirmationStartedAt[phraseHash] > 0) {
                uint256 startedAt = confirmationStartedAt[phraseHash];
                uint256 expirationTime = startedAt + info.confirmationDelaySeconds + info.confirmationPeriodSeconds;

                if (block.timestamp > expirationTime) {
                    address oldOwner = info.owner;

                    info.owner = admin;
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

    function transferOwnershipImmediately(bytes32 phraseHash, address newOwner) external onlyOwner(phraseHash) {
        PhraseInfo storage info = phrases[phraseHash];

        address oldOwner = info.owner;
        info.owner = newOwner;

        emit OwnershipTransferred(phraseHash, oldOwner, newOwner);
    }

    function changeStatusToAwaitingConfirmation(bytes32 phraseHash) external onlyAdmin {
        require(phraseExists(phraseHash), "Phrase does not exist");

        PhraseInfo storage info = phrases[phraseHash];
        require(info.status == PhraseStatus.Created, "Status must be Created");

        info.status = PhraseStatus.ConfirmationAwaiting;
        confirmationStartedAt[phraseHash] = block.timestamp;
    }

    function deletePhrase(bytes32 phraseHash) external onlyAdmin {
        PhraseInfo storage info = phrases[phraseHash];
        require(info.owner == admin, "Phrase owner is not admin");

        delete phrases[phraseHash];
        delete confirmationStartedAt[phraseHash];

        emit PhraseDeleted(phraseHash, msg.sender);
    }

    function getPhraseInfo(bytes32 phraseHash) external view returns (
        address owner,
        PhraseStatus status,
        uint confirmationDelaySeconds,
        uint confirmationPeriodSeconds,
        uint confirmationStartedTimestamp,
        bytes32 claimHash
    ) {
        PhraseInfo memory info = phrases[phraseHash];
        return (
            info.owner,
            info.status,
            info.confirmationDelaySeconds,
            info.confirmationPeriodSeconds,
            confirmationStartedAt[phraseHash],
            info.claimHash
        );
    }

    function phraseExists(bytes32 phraseHash) public view returns (bool) {
        return phrases[phraseHash].exists == true;
    }
} 
