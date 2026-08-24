# AppData

View and access the data of your apps by either swiping up on the icon or from the force touch menu.

Compatible with iOS 11, 12, 13 and 14

## Features
<ul>
    <li>View the app bundle version and size</li>
    <li>View and copy the app bundle identifier</li>
    <li>Clear or update the app badge count</li>
    <li>Check the app data/caches size and clear them</li>
    <li>Offload apps by uninstalling them and keeping data</li>
    <li>Reset apps permissions</li>
    <li>Access the app bundle & data containers</li>
    <li>Access the app container groups</li>
    <li>Open the AppStore page of the app</li>
</ul>

## Historical App Store versions

The downgrade UI resolves an App Store track ID with Apple's iTunes Lookup API,
then queries Timbrd, Agzy, and Bilin in that order. Valid records from all
available providers are normalized and merged, using `versionId + version` as
the deduplication key. Network, HTTP, malformed JSON, empty, and invalid-record
responses are logged without authentication data and do not prevent the next
provider from being tried.

Only public version metadata is queried from these providers. Existing on-device
StoreServices code submits the selected external version ID; this project does
not send Apple credentials, cookies, DSIDs, or tokens to a history provider.
Version lookup no longer reads or compares the local App Store account and the
app purchaser account. Download submission reuses the device's active App Store
session; any password or biometric request remains controlled by iOS.

Download submission dynamically loads `AppStoreDaemon.framework` and sends an
`ASDPurchase` redownload request containing the selected external version ID.
Runtime class, singleton, and selector checks protect SpringBoard across iOS
versions. If the daemon API is unavailable or rejects the request, AppData falls
back to the existing dynamically loaded `StoreKitUI.framework` purchase path.

## Package removal safety

The package identifier is `com.moxuan.appdata` and it replaces the former
`com.iosdump.appdata` package. AppData installs only its own injection files in
ElleKit's native `usr/lib/TweakInject` directory. The package data contains no
`Library/MobileSubstrate` compatibility path and no ElleKit binary or loader.
There are no removal scripts. A narrowly scoped `postinst configure` migration
can restore a completely missing legacy compatibility link after upgrading from
AppData 1.8.8 or earlier. Because this repository packages explicit RootHide
paths, that migration checks `/var/jb/usr/lib/TweakInject` and restores the
matching `/var/jb/Library/MobileSubstrate/DynamicLibraries` entry. It never
overwrites an existing path or modifies the TweakInject target.

## Per-app automatic cache clearing

Long-pressing the cache action toggles automatic clearing for the application
whose AppData panel is open. The preference is stored under that application's
bundle identifier; it is not a global cache switch. On a permitted launch,
AppData clears only the selected application's `Library/Caches` and `tmp`
contents, with duplicate launch requests coalesced while a clear is running.

## Screenshot

<img src="https://raw.githubusercontent.com/FouadRaheb/AppData/master/Screenshots/1.jpg" width="350"> <img src="https://raw.githubusercontent.com/FouadRaheb/AppData/master/Screenshots/2.jpg" width="350">
