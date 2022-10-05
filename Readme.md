### Installation
1. Compile `AssetsParser.swift'` (or download executable) and place it somewhere (eg. in project root).
2. Add new `Run Script Phase` in `Build Phases` of a target.
3. Drag the new `Run Script` phase **above** the `Compile Sources` phase and paste the following:  
    ```bash
    f=$(find $SRCROOT -type f | grep -m 1 assets_parser)
    if [ f ]; then
        eval $f --dir "dir-to-scan"
    else
        echo "Warning: Assets parser executable not found"
    fi
   ```
4. Add `$SRCROOT/Assets.swift` to the "Output Files" of the Build Phase.
5. Uncheck "Based on dependency analysis" so that the script will be run on each build.
6. Build project, drag the `Assets.swift` files into your project and **uncheck** `Copy items if needed`.

### Usage
```swift
// SwiftUI
Image(Images.app.goodDog)
    .background(Color.app.primaryColor)
// UIKit
let image = UIImage(Images.app.goodCat)
let color = UIColor(.app.primaryColor)
```
