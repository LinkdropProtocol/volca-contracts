pragma solidity >= 0.5.6;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

/**
 * @title Linkdrop ERC721 Contract
 * @dev Contract sends NFTs from linkdropper's account to receiver on claim.
 * 
 * When deploying contract, linkdropper provides linkdrop parameters: 
 * (NFT address, linkdrop verification address).
 * 
 * Linkdrop verification address is used to verify that links are signed by LINKDROPPER. 
 * 
 * Linkdropper generates claim links. Each link contains an ephemeral private key 
 * signed by the private key corresponding to linkdrop verification address. 
 * The ephemeral private key assigned to link can only! be used once to sign receiver's address
 * Receiver claims NFT by providing signature to the Relayer Server, 
 * which then calls smart contract to claim NFT
 * 
 * On claim smart contract verifies that receiver provided address signed 
 * with ephemeral private key assigned to the link. 
 * If everything is correct, smart contract sends NFT to receiver.
 * 
 */

contract LinkdropERC721 is Pausable {

    // NFT to be ditributed
    address public NFT_ADDRESS;

    // address that holds NFTs to distribute (owner of this contract)
    address payable public LINKDROPPER; 

    // special address, used on claim to verify that links signed by the LINKDROPPER
    address public LINKDROP_VERIFICATION_ADDRESS; 
  
    //Indicates whether the link was used or not                                                                                                                 
    mapping (address => address) claimed;  

    event Claimed(address indexed linkKeyAddress, uint indexed tokenId, address receiver, uint timestamp);
  
    /**
    * @dev Contructor that sets linkdrop params 
    * @param _NFTAddress address NFT contract address to distribute
    * @param _linkdropVerificationAddress special address, used on claim to 
    *        verify that links signed by the linkdropper
    */
    constructor
    (
        address _NFTAddress,
        address _linkdropVerificationAddress
    ) 
    public 
    {
        LINKDROPPER = msg.sender;
        NFT_ADDRESS = _NFTAddress;
        LINKDROP_VERIFICATION_ADDRESS = _linkdropVerificationAddress;
    }
  
    /**
    * @dev Verify that address corresponding to link key is signed with linkdrop verification key
    * @param _linkKeyAddress address corresponding to link key
    * @param _tokenId tokenId attached to link 
    * @param _signature ECDSA signature
    * @return True if signature is correct.
    */
    function verifyLinkKey
    (
		address _linkKeyAddress,
		uint256 _tokenId,
		bytes memory _signature
    )
    public view 
    returns (bool) 
    {
        bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(_linkKeyAddress, _tokenId)));
        address signer = ECDSA.recover(prefixedHash, _signature);
        return signer == LINKDROP_VERIFICATION_ADDRESS;
    }
  
    /**
    * @dev Verify that address to receive NFTs is signed with link key
    * @param _linkKeyAddress address corresponding to link key
    * @param _receiver address to receive NFT.
    * @param _signature ECDSA signature
    * @return True if signature is correct.
    */
    function verifyReceiverAddress
    (
		address _linkKeyAddress,
	    address _receiver,
		bytes memory _signature
    )
    public pure 
    returns (bool) 
    {
        bytes32 prefixedHash = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(_receiver)));
        address signer = ECDSA.recover(prefixedHash, _signature);
        return signer == _linkKeyAddress;
    }

    /**
    * @dev Verify that claim params are correct and the link's ephemeral key wasn't used before.  
    * @param _receiver address to receive tokens.
    * @param _tokenId tokenId attached to link 
    * @param _linkKeyAddress address that corresponds to link key
    * @param _linkdropperSignature ECDSA signature. Signed by linkdrop verification key.
    * @param _receiverSignature ECDSA signature. Signed by link key
    */
    function checkClaimParams
    (
        address _receiver, 
		uint256 _tokenId, 
		address _linkKeyAddress,
		bytes memory _linkdropperSignature,
		bytes memory _receiverSignature
    )
    public view
    returns (bool)
    {
        // verify that link wasn't claimed before  
        require(isClaimedLink(_linkKeyAddress) == false, "Link has already been claimed");

        // verify that ephemeral key is legit and signed by LINKDROP_VERIFICATION_ADDRESS's key
        require
        (
            verifyLinkKey(_linkKeyAddress, _tokenId, _linkdropperSignature), 
            "Link key is not signed by linkdrop verification key"
        );
    
        // verify that receiver address is signed by ephemeral key assigned to claim link
        require
        (
            verifyReceiverAddress(_linkKeyAddress, _receiver, _receiverSignature), 
            "Receiver address is not signed by link key"
        );

        return true;
    }
  
    /**
    * @dev Claim NFT to receiver address if claim params are correct.
    * @param _receiver address to receive tokens.
    * @param _tokenId token id to be sent
    * @param _linkKeyAddress address corresponding to link key 
    * @param _linkdropperSignature ECDSA signature. Signed by the airdrop transit key.
    * @param _receiverSignature ECDSA signature. Signed by the link's ephemeral key.
    * @return True if NFT was successfully sent to receiver.
    */
    function claim
    (
		address _receiver, 
		uint256 _tokenId, 
		address _linkKeyAddress,
		bytes memory _linkdropperSignature,
		bytes memory _receiverSignature
	)
    public
    whenNotPaused
    returns (bool) 
    {
        require
        (
            checkClaimParams
            (
                _receiver,
                _tokenId,
                _linkKeyAddress,
                _linkdropperSignature,
                _receiverSignature
            ),
            "Invalid claim params"
        );

        // mark link as claimed
        claimed[_linkKeyAddress] = _receiver;			
    
        // send NFT
        IERC721(NFT_ADDRESS).transferFrom(LINKDROPPER, _receiver, _tokenId);
           
        // log claim
        emit Claimed(_linkKeyAddress, _tokenId, _receiver, now);    
        
        return true;
    }

    /**
    * @dev Get boolean if link is already claimed. 
    * @param _linkKeyAddress address corresponding to link key
    * @return True if the transit address was already used. 
    */
    function isClaimedLink(address _linkKeyAddress) 
    public view returns (bool) 
    {
        return linkClaimedTo(_linkKeyAddress) != address(0);
    }

    /**
    * @dev Get receiver for claimed link
    * @param _linkKeyAddress address corresponding to link key
    * @return True if the transit address was already used. 
    */
    function linkClaimedTo(address _linkKeyAddress) 
    public view 
    returns (address) 
    {
        return claimed[_linkKeyAddress];
    }

}