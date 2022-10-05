import Foundation

// MARK: - Main
@main
enum Main {
    static func main() {
        var configuration = getConfiguration(from: CommandLine.arguments)
        guard let parseDir = configuration.parseDir else {
            Log.send("Parse dir has not been defined in arguments.", level: .error)
            return
        }
        guard var assetsPath = try? eval("find \(parseDir) -type d | grep -m 1 Assets.xcassets", shell: configuration.shellDir) else {
            Log.send("Cannot execute shell script. Check parser configuration file.", level: .warning)
            return
        }
        assetsPath = assetsPath.replacingOccurrences(of: "\n", with: "")
        guard !assetsPath.isEmpty else {
            Log.send("Assets directory not found.", level: .warning)
            return
        }
        configuration.assetsPath = assetsPath

        let parser = AssetsParser(configuration: configuration)
        parser.generate()
    }

    static func getConfiguration(from arguments: [String]) -> AssetsParser.Configuration {
        var configuration = AssetsParser.Configuration()
        for (i, cmd) in arguments.enumerated() {
            switch cmd {
            case "--dir":
                configuration.parseDir = arguments[i+1]
            case "--output":
                configuration.outputPath = arguments[i+1]
            case "--names":
                configuration.allowedNames = arguments[i+1]
            case "--shell":
                configuration.shellDir = arguments[i+1]
            default:
                break
            }
        }
        return configuration
    }
}

// MARK: - Assets parser

struct AssetsParser {
    let configuration: Configuration
    let fileManager = FileManager.default
    
    func generate() {
        // Construct assets structure
        let imagesRoot = composeAssetsTree(name: configuration.imagesDir, path: configuration.assetsPath)
        let colorsRoot = composeAssetsTree(name: configuration.colorsDir, path: configuration.assetsPath)
        guard let imagesRoot = imagesRoot, let colorsRoot = colorsRoot else {
            Log.send("No assets found.", level: .warning)
            return
        }
        guard imagesRoot.children != nil,
              !imagesRoot.children!.isEmpty,
              colorsRoot.children != nil,
              !colorsRoot.children!.isEmpty else {
            Log.send("No assets found.", level: .warning)
            return
        }
        // Get assets source code
        let sourceString = composeSourceString(images: imagesRoot, colors: colorsRoot)
        // Write source code to file
        createAssetsFile(sourceString: sourceString)
    }
    
    /// Parse directory and compose a tree from it's content.
    /// - Parameters:
    ///   - name: name of currently passing directory
    ///   - path: origin path
    /// - Returns: object that represents current directory as node
    private func composeAssetsTree(name: String, path: String) -> Node? {
        var node: Node? = nil
        if name.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil {
            let content = try? fileManager.contentsOfDirectory(atPath: path + "/" + name)
            node = .init(type: .container, name: name)
            node!.children = content?.compactMap { composeAssetsTree(name: $0, path: path + "/" + name) }
            // Remove directory if empty
            if (node!.children == nil || node!.children!.isEmpty) {
                node = nil
            }
        } else if (name.contains(".imageset") || name.contains(".colorset")) {
            node = .init(type: .content, name: String(name.dropLast(9)))
        }
        return node
    }
    
    
    /// Produce assets Swift code from given `Node`, in string representation.
    /// - Parameter node: node to process
    /// - Returns: code string
    func generateAssetsCode(node: Node, ofType type: Self.AssetsType) -> String {
        func makeVariables(from nodes: [Node], indent: Int) -> String {
            let t = String(repeating: "\t", count: indent)
            var variables = ""
            for node in nodes where node.type == .content {
                switch type {
                case .images: variables.append("\(t)case \(node.name.lowercasingFirstLetter())\n")
                case .colors(let type): variables.append("\(t)static var \(node.name.lowercasingFirstLetter()): \(type) { \(type)(\"\(node.name)\") }\n")
                }
            }
            return variables
        }
        
        func makeType(node: Node, indent: Int) -> String {
            let t = String(repeating: "\t", count: indent)
            var entity = ""
            switch type {
            case .images: entity = "\(t)enum \(node.name.lowercased()): String {\n"
            case .colors: entity = "\(t)enum \(node.name.lowercased()) {\n"
            }
            if node.children != nil {
                entity.append(makeVariables(from: node.children!, indent: indent + 1))
            }
            if let nestedEntity = node.children?
                .filter({ $0.type == .container })
                .compactMap({ makeType(node: $0, indent: indent + 1) })
                .reduce("", +),
               !nestedEntity.isEmpty {
                entity.append("\n")
                entity.append(nestedEntity)
            }
            entity.append("\(t)}\n")
            return entity
        }
        
        var node = node
        node.name = configuration.namespaceName
        let program = makeType(node: node, indent: 1)
        return program
    }
    
    func composeSourceString(images: Node, colors: Node) -> String {
            """
        import SwiftUI
        
        // MARK: - Inits

        extension UIImage {
            convenience init<T: RawRepresentable>(_ asset: T) where T.RawValue: StringProtocol {
                self.init(named: asset.rawValue as! String)!
            }
        }

        extension Image {
            init<T: RawRepresentable>(_ asset: T) where T.RawValue: StringProtocol {
                self.init(name: asset.rawValue as! String)
            }
        }

        extension UIColor {
            convenience init(_ name: String) {
                self.init(named: name)!
            }
        }
        
        // MARK: - Extensions

        struct Images {
        \(generateAssetsCode(node: images, ofType: .images))
        }

        extension Color {
        \(generateAssetsCode(node: colors, ofType: .colors("Color")))
        }

        extension UIColor {
        \(generateAssetsCode(node: colors, ofType: .colors("UIColor")))
        }
        """
    }
    
    private func createAssetsFile(sourceString: String) {
        guard let data = sourceString.data(using: .utf8) else {
            Log.send("Could not get data object from generated source code", level: .error)
            return
        }
        fileManager.createFile(atPath: configuration.outputPath, contents: data)
    }
}

extension AssetsParser {
    struct Configuration {
        let namespaceName: String = "app"
        var imagesDir: String = "Images"
        var colorsDir: String = "Colors"
        var parseDir: String!
        var assetsPath: String!
        var outputPath: String = "./Assets.swift"
        var allowedNames: String = "^[a-zA-Z0-9_]+$"
        var shellDir: String = "/bin/sh"
    }
    
    struct Node {
        enum NodeType { case container, content }
        var type: NodeType
        var name: String
        var children: [Node]?
    }
    
    enum AssetsType {
        case images
        case colors(_ data: String)
    }
}

// MARK: - Tools
extension String {
    func capitalizingFirstLetter() -> String {
      return prefix(1).uppercased() + self.lowercased().dropFirst()
    }
    
    func lowercasingFirstLetter() -> String {
        return prefix(1).lowercased() + self.dropFirst()
    }

    mutating func capitalizeFirstLetter() {
      self = self.capitalizingFirstLetter()
    }
    
    mutating func lowercaseFirstLetter() {
      self = self.lowercasingFirstLetter()
    }
}

struct Log {
    enum LogType: String {
        case info
        case warning
        case error
        var icon: String {
            switch self {
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "🛑"
            }
        }
    }
    static func send(_ message: String, level: LogType) {
        print("\(level.icon) [AssetsParser][\(level.rawValue.uppercased())]: \(message)")
    }
}

@discardableResult
func eval(_ command: String, shell: String) throws -> String? {
    let process = Process()
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.arguments = ["-c", command]
    process.executableURL = URL(fileURLWithPath: shell)
    process.standardInput = nil
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)
    return output
}

