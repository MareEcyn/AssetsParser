import Foundation

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

@main
enum Main {
    static func main() {
        let parser = AssetsParser()
        parser.generateAssets()
    }
}

struct AssetsParser {
    let assetsUrl: String = CommandLine.arguments[1]
    let imagesDirName: String = "Images"
    let colorsDirName: String = "Colors"
    
    let fileManager = FileManager.default
    
    let integrationCode: String = """
import SwiftUI

// MARK: - Integration code

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
"""
    
    func generateAssets() {
        // Generate code for images assets
        guard let imagesRoot = composeAssetsTree(name: imagesDirName, path: assetsUrl) else {
            preconditionFailure("Images directory isn't exist.")
        }
        guard imagesRoot.children != nil, !imagesRoot.children!.isEmpty else {
            preconditionFailure("Images directory is empty")
        }
        guard let colorsRoot = composeAssetsTree(name: colorsDirName, path: assetsUrl) else {
            preconditionFailure("Colors directory isn't exist.")
        }
        guard colorsRoot.children != nil, !colorsRoot.children!.isEmpty else {
            preconditionFailure("Colors directory is empty")
        }
        let sourceString = """
\(integrationCode)\n

// MARK: - Assets

struct Images {
\(generateImageAssets(node: imagesRoot))
}

extension Color {
\(generateColorAssets(node: colorsRoot, typeName: "Color"))
}

extension UIColor {
\(generateColorAssets(node: colorsRoot, typeName: "UIColor"))
}
"""
        createAssetsFile(sourceString: sourceString)
    }
    
    func tab(_ count: Int) -> String {
        String(repeating: "\t", count: count)
    }
    
    
    /// Parse root images directory and compose a tree from it's content.
    /// - Parameters:
    ///   - name: name of currently passing directory
    ///   - path: origin path
    /// - Returns: object that represents current image directory as node
    private func composeAssetsTree(name: String, path: String) -> Node? {
        var node: Node? = nil
        if name.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil {
            let content = try? fileManager.contentsOfDirectory(atPath: path + "/" + name)
            node = .init(type: .container, name: name)
            node!.children = content?.compactMap { composeAssetsTree(name: $0, path: path + "/" + name) }
            // Remove container if empty
            if (node!.children == nil || node!.children!.isEmpty) {
                node = nil
            }
        } else if (name.contains(".imageset") || name.contains(".colorset")) {
            node = .init(type: .content, name: String(name.dropLast(9)))
        }
        return node
    }
    
    
    /// Produce images assets Swift code from given `Node`, in string representation.
    /// - Parameter node: node to process
    /// - Returns: code string
    private func generateImageAssets(node: Node) -> String {
        func makeVariables(from nodes: [Node], tabCount: Int) -> String {
            var variables = ""
            for node in nodes where node.type == .content {
                variables.append("\(tab(tabCount))case \(node.name.lowercasingFirstLetter())\n")
            }
            return variables
        }
        
        func makeType(node: Node, tabCount: Int) -> String {
            var entity = "\(tab(tabCount))enum \(node.name.lowercased()): String {\n"
            if node.children != nil {
                entity.append(makeVariables(from: node.children!, tabCount: tabCount + 1))
            }
            if let nestedEntity = node.children?.filter { $0.type == .container }.compactMap { makeType(node: $0, tabCount: tabCount + 1) }.reduce("", +),
            !nestedEntity.isEmpty {
                entity.append("\n")
                entity.append(nestedEntity)
            }
            entity.append("\(tab(tabCount))}\n")
            return entity
        }
        
        var node = node
        node.name = "app"
        let program = makeType(node: node, tabCount: 1)
        return program
    }
    
    /// Produce colors assets Swift code from given `Node`, in string representation.
    /// - Parameter node: node to process
    /// - Returns: color assets code
    private func generateColorAssets(node: Node, typeName: String) -> String {
        func makeVariables(from nodes: [Node], tabCount: Int) -> String {
            var variables = ""
            for node in nodes where node.type == .content {
                variables.append("\(tab(tabCount))static var \(node.name.lowercasingFirstLetter()): \(typeName) { \(typeName)(\"\(node.name)\") }\n")
            }
            return variables
        }
        
        func makeType(node: Node, tabCount: Int) -> String {
            var entity = "\(tab(tabCount))enum \(node.name.lowercased()) {\n"
            if node.children != nil {
                entity.append(makeVariables(from: node.children!, tabCount: tabCount + 1))
            }
            if let nestedEntity = node.children?.filter { $0.type == .container }.compactMap { makeType(node: $0, tabCount: tabCount + 1) }.reduce("", +),
            !nestedEntity.isEmpty {
                entity.append("\n")
                entity.append(nestedEntity)
            }
            entity.append("\(tab(tabCount))}\n")
            return entity
        }
        
        var node = node
        node.name = "app"
        let colorAssets = makeType(node: node, tabCount: 1)
        return colorAssets
    }
    
    private func createAssetsFile(sourceString: String) {
        let path = URL(fileURLWithPath: #file).deletingLastPathComponent().relativePath + "/iosApp/Presentation/View/Assets.swift"
        let data = sourceString.data(using: .utf8)
        fileManager.createFile(atPath: path, contents: data)
    }
}

extension AssetsParser {
    struct Node {
        enum NodeType { case container, content }
        var type: NodeType
        var name: String
        var children: [Node]?
    }
}
