# Site Monitor

A small macOS menu bar app that keeps an eye on your websites. It checks each site on a schedule and tells you when something goes wrong.

- **Up or down**: any HTTP error or unanswered request, double-checked before it alerts you
- **Response time**: with a sparkline of the last 30 checks
- **SSL certificates**: warns 14 days before one expires
- **Page content**: optionally checks that a page contains a piece of text
- **Inertia SSR**: optionally warns when a Laravel/Inertia page comes back without server-side rendering
- **Notifications** when a site goes down, needs attention, or comes back up
- Pauses while your Mac sleeps or is offline, so you don't get false alarms

> [!NOTE]
> Site Monitor is in beta. If something doesn't work, please [open an issue](https://github.com/gillesserrien/site-monitor/issues).

## Requirements

macOS 26 (Tahoe) or later, on an Apple Silicon or Intel Mac.

## Install

1. Download the latest `SiteMonitor-….dmg` from the [Releases page](https://github.com/gillesserrien/site-monitor/releases).
2. Open the disk image and drag **SiteMonitor** into your **Applications** folder.
3. Open SiteMonitor from Applications. macOS says it can't verify the app, because the beta isn't notarized by Apple yet. Click **Done**.
4. Open **System Settings › Privacy & Security**, scroll down to the message saying SiteMonitor was blocked, and click **Open Anyway**. Confirm with your password or Touch ID.

You only have to do this the first time. If you prefer Terminal, this does the same as steps 3 and 4:

```sh
xattr -dr com.apple.quarantine /Applications/SiteMonitor.app
```

### Build from source instead

You need [Xcode](https://apps.apple.com/app/xcode/id497799835) 27 or later (free). Open it once after installing so it can finish setting up, then run:

```sh
git clone https://github.com/gillesserrien/site-monitor.git
cd site-monitor
xcodebuild -project SiteMonitor.xcodeproj -scheme SiteMonitor -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build -quiet
ditto build/Build/Products/Release/SiteMonitor.app /Applications/SiteMonitor.app
open /Applications/SiteMonitor.app
```

You don't need an Apple Developer account. Xcode signs the app so it runs on your own Mac, and an app you built yourself skips the "Open Anyway" step.

## Getting started

1. Find the new icon in your menu bar. Site Monitor has no Dock icon or window; everything happens from the menu bar.
2. Allow notifications when macOS asks, so you hear about problems.
3. Click the icon, choose **Add site** and enter a web address.
4. Open the gear menu and turn on **Open at Login** so monitoring starts with your Mac.

In the same gear menu you can choose how often to check: every 30 seconds, 1 minute (default), 5 minutes or 15 minutes.

## Using it

The menu bar icon always shows the worst status across all your sites.

| Status | Meaning |
| --- | --- |
| 🟢 Up | Responded normally |
| 🟠 Slow | Took longer than 2 seconds to respond |
| 🟠 Needs attention | Up, but the expected text is missing, Inertia SSR is off, or the SSL certificate expires within 14 days |
| 🔴 Down | HTTP error, no response, or an SSL problem. A failed check is retried once before the site counts as down |

Click a site to open it in your browser. Right-click it to edit or remove it. Use **Activity** to see the most recent status changes.

## Updating

Quit Site Monitor from the gear menu, then install the new version the same way you installed the first one: drag the new download into Applications and replace the old copy, or run `git pull` followed by the build commands above. Your sites and settings are kept.

## Uninstall

1. Turn off **Open at Login** in the gear menu, then choose **Quit Site Monitor**.
2. Delete the app and its data:

   ```sh
   rm -rf /Applications/SiteMonitor.app
   rm -rf ~/Library/Containers/eu.compactcode.SiteMonitor
   ```

## Troubleshooting

**The icon doesn't appear in the menu bar.** The menu bar may be full, or the icon may be hidden behind the camera notch. Try quitting a few other menu bar apps, and check that Site Monitor is allowed in **System Settings › Menu Bar**.

**No notifications.** Turn them on in **System Settings › Notifications › Site Monitor**.

**Open at Login doesn't stick.** macOS may want you to approve it. The app opens **System Settings › General › Login Items & Extensions** for you; switch Site Monitor on there.

**`xcodebuild` says it requires Xcode, but the active developer directory is a command line tools instance.** Point the command line at Xcode, then build again:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

**`xcodebuild` asks you to agree to the license.** Run `sudo xcodebuild -license accept`.

## Privacy

Site Monitor only connects to the sites you add. If a site doesn't answer at all, it also loads Apple's connectivity check page (`apple.com/library/test/success.html`) to tell whether the site is down or your own internet is. There are no accounts and no analytics. Your site list is stored on your Mac in `~/Library/Containers/eu.compactcode.SiteMonitor/Data/Library/Application Support/SiteMonitor/sites.json`.

## Development

Open `SiteMonitor.xcodeproj` in Xcode and press ⌘R to run the app straight from Xcode. SwiftUI previews are available for `MonitorView` and `SiteRow`.

## License

[MIT](LICENSE)
