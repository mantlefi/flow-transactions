import NonFungibleToken from 0x1d7e57aa55817448
import FlowToken from 0x1654653399040a61
import FungibleToken from 0xf233dcee88fe0abe
import FUSD from 0x3c5959b568896393
import Profile from 0x097bafa4e0b48eef
import FIND from 0x097bafa4e0b48eef
import CharityNFT from 0x097bafa4e0b48eef

transaction(name: String, amount: UFix64, message:String) {

	prepare(account: AuthAccount) {

		let charityCap = account.getCapability<&{NonFungibleToken.CollectionPublic}>(CharityNFT.CollectionPublicPath)

		if !charityCap.check() {
			account.save<@NonFungibleToken.Collection>(<- CharityNFT.createEmptyCollection(), to: CharityNFT.CollectionStoragePath)
			account.link<&{NonFungibleToken.CollectionPublic}>(CharityNFT.CollectionPublicPath, target: CharityNFT.CollectionStoragePath)
		}

		let fusdReceiver = account.getCapability<&{FungibleToken.Receiver}>(/public/fusdReceiver)
		if !fusdReceiver.check() {
			let fusd <- FUSD.createEmptyVault()
			account.save(<- fusd, to: /storage/fusdVault)
			account.link<&FUSD.Vault{FungibleToken.Receiver}>( /public/fusdReceiver, target: /storage/fusdVault)
			account.link<&FUSD.Vault{FungibleToken.Balance}>( /public/fusdBalance, target: /storage/fusdVault)
		}

		let leaseCollection = account.getCapability<&FIND.LeaseCollection{FIND.LeaseCollectionPublic}>(FIND.LeasePublicPath)
		if !leaseCollection.check() {
			account.unlink(FIND.LeasePublicPath)
			destroy <- account.load<@AnyResource>(from:FIND.LeaseStoragePath)

			account.save(<- FIND.createEmptyLeaseCollection(), to: FIND.LeaseStoragePath)
			account.link<&FIND.LeaseCollection{FIND.LeaseCollectionPublic}>( FIND.LeasePublicPath, target: FIND.LeaseStoragePath)
		}

		let bidCollection = account.getCapability<&FIND.BidCollection{FIND.BidCollectionPublic}>(FIND.BidPublicPath)
		if !bidCollection.check() {
			account.unlink(FIND.BidPublicPath)
			destroy <- account.load<@AnyResource>(from:FIND.BidStoragePath)

			account.save(<- FIND.createEmptyBidCollection(receiver: fusdReceiver, leases: leaseCollection), to: FIND.BidStoragePath)
			account.link<&FIND.BidCollection{FIND.BidCollectionPublic}>( FIND.BidPublicPath, target: FIND.BidStoragePath)
		}

		let profileCap = account.getCapability<&{Profile.Public}>(Profile.publicPath)
		if !profileCap.check() {
			account.unlink(Profile.publicPath)
			destroy <- account.load<@AnyResource>(from:Profile.storagePath)

			let profileName = account.address.toString()

			let profile <-Profile.createUser(name:profileName, createdAt: "find")

			let fusdWallet=Profile.Wallet( name:"FUSD", receiver:fusdReceiver, balance:account.getCapability<&{FungibleToken.Balance}>(/public/fusdBalance), accept: Type<@FUSD.Vault>(), names: ["fusd", "stablecoin"])

			profile.addWallet(fusdWallet)

			let flowWallet=Profile.Wallet(
				name:"Flow", 
				receiver:account.getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver),
				balance:account.getCapability<&{FungibleToken.Balance}>(/public/flowTokenBalance),
				accept: Type<@FlowToken.Vault>(),
				names: ["flow"]
			)
	
			profile.addWallet(flowWallet)
			profile.addCollection(Profile.ResourceCollection("FINDLeases",leaseCollection, Type<&FIND.LeaseCollection{FIND.LeaseCollectionPublic}>(), ["find", "leases"]))
			profile.addCollection(Profile.ResourceCollection("FINDBids", bidCollection, Type<&FIND.BidCollection{FIND.BidCollectionPublic}>(), ["find", "bids"]))

			account.save(<-profile, to: Profile.storagePath)
			account.link<&Profile.User{Profile.Public}>(Profile.publicPath, target: Profile.storagePath)
			account.link<&{FungibleToken.Receiver}>(Profile.publicReceiverPath, target: Profile.storagePath)
		}

		let profile =account.borrow<&Profile.User>(from:Profile.storagePath)!

		let strLength = amount.toString().length
		let amountString = amount.toString().slice(from: 0, upTo: strLength-6)
		profile.verify(profile.getName().concat(" sent ").concat(amountString).concat(" FUSD with message:").concat(message))

		let vaultRef = account.borrow<&FUSD.Vault>(from: /storage/fusdVault) ?? panic("Could not borrow reference to the fusdVault!")
		FIND.deposit(to: name, from: <- vaultRef.withdraw(amount: amount))

	}

}