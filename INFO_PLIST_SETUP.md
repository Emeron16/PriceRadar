# Info.plist Configuration for PriceRadar

After creating the Xcode project, you **must** add the following privacy descriptions to your `Info.plist` file.

## Required Privacy Permissions

The app requires two critical permissions:

### 1. Camera Access (for Barcode Scanning)
**Key:** `NSCameraUsageDescription`
**Value:** `PriceRadar needs camera access to scan product barcodes`

### 2. Location Access (for Finding Nearby Stores)
**Key:** `NSLocationWhenInUseUsageDescription`
**Value:** `PriceRadar needs your location to find nearby stores with better prices`

## How to Add to Info.plist

### Method 1: Using Xcode UI (Recommended)

1. Open your Xcode project
2. Select the **PriceRadar** target in the project navigator
3. Go to the **Info** tab
4. Click the **+** button to add a new key
5. Add the following entries:

   | Key | Type | Value |
   |-----|------|-------|
   | Privacy - Camera Usage Description | String | PriceRadar needs camera access to scan product barcodes |
   | Privacy - Location When In Use Usage Description | String | PriceRadar needs your location to find nearby stores with better prices |

### Method 2: Editing Info.plist Directly

Right-click on `Info.plist` → Open As → Source Code, then add:

```xml
<key>NSCameraUsageDescription</key>
<string>PriceRadar needs camera access to scan product barcodes</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>PriceRadar needs your location to find nearby stores with better prices</string>
```

## ⚠️ Important Notes

- **Without these permissions, the app will crash** when trying to access the camera or location
- These descriptions are shown to users when requesting permissions
- Make the descriptions clear and user-friendly
- iOS requires these before accessing hardware features

## Testing Permissions

After adding these keys:

1. Run the app on a simulator or device
2. You should see permission prompts when:
   - Opening the Scanner tab (camera permission)
   - The app tries to get your location (location permission)
3. Grant both permissions to test full functionality

## Troubleshooting

**App crashes when opening scanner:**
- Verify `NSCameraUsageDescription` is added to Info.plist

**Location not working:**
- Verify `NSLocationWhenInUseUsageDescription` is added to Info.plist
- Check device Settings → Privacy → Location Services is enabled
- Check app-specific location permission is enabled

**Permission prompts not appearing:**
- Clean build folder (Product → Clean Build Folder)
- Delete app from device/simulator and reinstall
- Reset simulator (Device → Erase All Content and Settings)
