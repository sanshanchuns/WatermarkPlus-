//
//
//  ContentView.swift
//  AddDatePrint
//
//  Created by leozhu on 2025/4/8.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AppKit
import CoreText

extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
    
    func localizedFormat(_ args: CVarArg...) -> String {
        String(format: self.localized, arguments: args)
    }
}

// 添加字体管理器委托类
class FontManagerDelegate: NSObject {
    static let shared = FontManagerDelegate()
    var onFontSelected: ((NSFont) -> Void)?
    
    private override init() {
        super.init()
        NSFontManager.shared.target = self
        NSFontManager.shared.action = #selector(changeFont(_:))
    }
    
    @objc func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager,
              let font = fontManager.selectedFont else { return }
        onFontSelected?(font)
    }
}

// 将辅助函数移到 ContentView 外部
private func showCenteredAlert(_ alert: NSAlert, relativeTo window: NSWindow) -> NSApplication.ModalResponse {
    // 获取父窗口的屏幕坐标和大小
    let parentFrame = window.frame
    let alertWindow = alert.window
    
    // 计算父窗口的中心点（考虑屏幕坐标系）
    let centerX = parentFrame.minX + (parentFrame.width / 2)
    let centerY = parentFrame.minY + (parentFrame.height / 2)
    
    // 计算弹窗的位置（将弹窗的中心点对齐到父窗口的中心点）
    let alertX = centerX - (alertWindow.frame.width / 2)
    let alertY = centerY - (alertWindow.frame.height / 2)
    
    // 设置弹窗位置
    alertWindow.setFrameOrigin(NSPoint(x: alertX, y: alertY))
    
    // 确保弹窗在父窗口之上
    alertWindow.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
    
    // 将弹窗设置为父窗口的子窗口
    window.addChildWindow(alertWindow, ordered: .above)
    
    return alert.runModal()
}

struct ContentView: View {
    @State private var selectedImages: [URL] = []
    @State private var processedCount = 0
    @State private var isTargeted = false
    @State private var isProcessing = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var selectedColor: NSColor = NSColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
    @State private var showColorPicker = false
    @State private var tempColor: NSColor = NSColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
    @State private var isCustomColor = false
    @State private var selectedFont: NSFont = NSFont.systemFont(ofSize: 24)
    @State private var showFontPicker = false
    @State private var isCustomFont = false
    @State private var unsupportedFormats: [String] = []
    @State private var defaultFontLoaded = false
    @State private var showDateFormatPicker = false
    @State private var isCustomDateFormat = false
    @FocusState private var focusedField: Field?
    @State private var previewImage: NSImage?
    @State private var selectedPreviewIndex: Int = 0
    @State private var isGeneratingPreview: Bool = false
    @State private var originalPreviewImage: NSImage?
    @State private var watermarkLayer: NSImage?
    @State private var isLoadingImage: Bool = false
    @State private var isRefreshingWatermark: Bool = false
    @State private var showFontPanel: Bool = false
    @State private var ledFont: NSFont = NSFont.systemFont(ofSize: 24)
    @State private var processProgress: Double = 0
    @State private var currentProcessingFile: String = ""
    @State private var currentTask: Task<Void, Never>?
    
    // 添加字体大小枚举
    enum FontSize: String, CaseIterable {
        case small = "small"
        case medium = "medium"
        case large = "large"
        
        var localizedName: String {
            switch self {
                case .small: return "小".localized
                case .medium: return "中".localized
                case .large: return "大".localized
            }
        }
        
        var scaleFactor: Double {
            switch self {
                case .small: return 0.02
                case .medium: return 0.025
                case .large: return 0.03
            }
        }
    }
    
    // 添加字体大小状态
    @State private var selectedFontSize: FontSize = .small
    
    // 定义可聚焦的字段枚举
    enum Field {
        case processButton
        case alertButton
    }
    
    // 预设日期格式
    private let presetDateFormats: [(name: String, format: String)] = [
        ("标准".localized, "yyyy-MM-dd"),
        ("简洁".localized, "yy.MM.dd"),
        ("斜杠".localized, "yyyy/MM/dd"),
        ("点号".localized, "yyyy.MM.dd")
    ]
    
    // 预设颜色
    private let presetColors: [(name: String, color: NSColor)] = [
        ("柯达黄".localized, NSColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)),
        ("橙红".localized, NSColor(red: 1.0, green: 0.2, blue: 0.0, alpha: 1.0)),
        ("玫红".localized, NSColor(red: 1.0, green: 0.2, blue: 0.6, alpha: 1.0)),
        ("天蓝".localized, NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)),
        ("翠绿".localized, NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0))
    ]
    
    // 支持的图片格式
    private let supportedImageExtensions = ["jpg", "jpeg", "png", "gif", "tiff", "bmp", "heic"]
    
    // 日期格式化器
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        return formatter
    }
    
    @State private var dateFormat: String = "yyyy-MM-dd"
    
    // 使用计算属性返回默认字体
    private var defaultFont: NSFont {
        return ledFont
    }
    
    // 添加处理文件夹的函数
    private func processDirectory(_ url: URL, newSelection: inout [URL]) {
        guard url.hasDirectoryPath else { return }
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == false {
                    let pathExtension = fileURL.pathExtension.lowercased()
                    if supportedImageExtensions.contains(pathExtension) {
                        newSelection.append(fileURL)
                    }
                }
            } catch {
                print("Error reading directory: \(error)")
            }
        }
    }
    
    var body: some View {
        HSplitView {
            // 左侧设置面板
        VStack(spacing: 20) {
                // 修改拖放区域
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .frame(height: 200)
                    .foregroundColor(.gray)
                    .contentShape(Rectangle())
                
                VStack {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                            Text("拖放照片或文件夹到这里\n或点击选择".localized)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .onTapGesture {
                selectFiles()
            }
                // 修改拖放处理
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    // 创建新的选择数组
                    var newSelection: [URL] = []
                    
                    let group = DispatchGroup()
                    
                for provider in providers {
                        group.enter()
                        
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                            if let urlData = urlData as? Data,
                               let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                            DispatchQueue.main.async {
                                    if url.hasDirectoryPath {
                                        // 处理文件夹
                                        processDirectory(url, newSelection: &newSelection)
                                    } else {
                                        // 处理单个文件
                                        let pathExtension = url.pathExtension.lowercased()
                                        if supportedImageExtensions.contains(pathExtension) {
                                            newSelection.append(url)
                                        }
                                    }
                                }
                            }
                            group.leave()
                        }
                    }
                    
                    // 当所有文件都处理完后，更新选择
                    group.notify(queue: .main) {
                        if !newSelection.isEmpty {
                            selectedImages = newSelection
                        }
                    }
                    
                return true
            }
            
            // 状态信息区域
            VStack(spacing: 5) {
                if !selectedImages.isEmpty {
                    Text("已选择 %d 张照片".localizedFormat(selectedImages.count))
                        .font(.headline)
                } else {
                    Text("")
                        .font(.headline)
                        .frame(height: 20)
                }
                
                if isProcessing {
                    ProgressView("正在处理".localized, value: Double(processedCount), total: Double(selectedImages.count))
                        .progressViewStyle(.linear)
                } else {
                    ProgressView("", value: 0, total: 1)
                        .progressViewStyle(.linear)
                        .opacity(0)
                        .frame(height: 20)
                }
            }
            .frame(height: 60)
            
                // 水印设置区域
                VStack(alignment: .leading, spacing: 15) {
                    // 日期格式选择
                    VStack(alignment: .leading) {
                        Text("日期格式".localized)
                            .font(.headline)
                        HStack {
                        ForEach(presetDateFormats, id: \.name) { preset in
                            Button(action: {
                                dateFormat = preset.format
                                    updateWatermarkLayer()
                            }) {
                                Text(preset.name)
                                    .frame(width: 60, height: 30)
                                    .background(dateFormat == preset.format ? Color.accentColor : Color.clear)
                                    .foregroundColor(dateFormat == preset.format ? .white : .primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                    // 添加字体大小选择
                    VStack(alignment: .leading) {
                        Text("字体大小".localized)
                        .font(.headline)
                            HStack {
                            ForEach(FontSize.allCases, id: \.self) { size in
                                Button(action: {
                                    selectedFontSize = size
                                    updateWatermarkLayer()
                                }) {
                                    Text(size.localizedName)
                                        .frame(width: 60, height: 30)
                                        .background(selectedFontSize == size ? Color.accentColor : Color.clear)
                                        .foregroundColor(selectedFontSize == size ? .white : .primary)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // 颜色选择
                    VStack(alignment: .leading) {
                    Text("水印颜色".localized)
                        .font(.headline)
                        HStack {
                        ForEach(presetColors, id: \.name) { preset in
                            Button(action: {
                                selectedColor = preset.color
                                isCustomColor = false
                                    updateWatermarkLayer()
                            }) {
                                Circle()
                                    .fill(Color(nsColor: preset.color))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                                    .stroke(selectedColor == preset.color ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        
                            // 自定义颜色选择区域
                            ZStack {
                                // 显示选择的自定义颜色
                            if isCustomColor {
                                Circle()
                                    .fill(Color(nsColor: selectedColor))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                                .stroke(Color.accentColor, lineWidth: 2)
                                        )
                                }
                                
                                // 调色板按钮
                                Button(action: {
                                    showColorPicker = true
                                }) {
                                    Image(systemName: "paintpalette.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(isCustomColor ? .primary : .accentColor)
                                }
                                .buttonStyle(.plain)
                                .offset(y: isCustomColor ? -40 : 0) // 选择自定义颜色后上浮
                                .animation(.spring(response: 0.3), value: isCustomColor)
                            }
                            .frame(width: 30, height: isCustomColor ? 70 : 30) // 调整高度以适应上浮的按钮
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    // 处理按钮
                    Button(action: {
                        processImages()
                    }) {
                        processButtonContent
                }
                .buttonStyle(.borderedProminent)
                    .disabled(selectedImages.isEmpty || isProcessing)
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color(.textBackgroundColor))
                .cornerRadius(12)
            
            Spacer()
        }
            .frame(minWidth: 300, maxWidth: 400)
            .padding()
            
            // 右侧预览区域
            VStack {
                if !selectedImages.isEmpty {
                    ZStack {
                        // 原始图片层
                        if let originalImage = originalPreviewImage {
                            Image(nsImage: originalImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        // 水印层
                        if let watermark = watermarkLayer {
                            Image(nsImage: watermark)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        if isLoadingImage {
                            ProgressView("加载图片中...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if isRefreshingWatermark {
                            VStack {
                                ProgressView("更新水印...")
                            }
                .padding()
                            .background(Color(.windowBackgroundColor).opacity(0.8))
                            .cornerRadius(8)
                        }
                    }
                    
                    // 预览图片选择器
                    if selectedImages.count > 1 {
                        HStack {
                            Button(action: {
                                if !isLoadingImage {
                                    selectedPreviewIndex = max(0, selectedPreviewIndex - 1)
                                }
                            }) {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(selectedPreviewIndex == 0 || isLoadingImage)
                            
                            Text("\(selectedPreviewIndex + 1) / \(selectedImages.count)")
                            
                            Button(action: {
                                if !isLoadingImage {
                                    selectedPreviewIndex = min(selectedImages.count - 1, selectedPreviewIndex + 1)
                                }
                            }) {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(selectedPreviewIndex == selectedImages.count - 1 || isLoadingImage)
                        }
                        .padding()
                    }
                } else {
                    Text("请选择图片以预览水印效果")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.textBackgroundColor))
        }
        .onChange(of: selectedImages) { _ in
            selectedPreviewIndex = 0
            loadOriginalImage()
        }
        .onChange(of: selectedColor) { _ in
            updateWatermarkLayer()
        }
        .onChange(of: dateFormat) { _ in
            updateWatermarkLayer()
        }
        .sheet(isPresented: $showColorPicker) {
            ColorPickerView(selectedColor: $selectedColor, isCustomColor: $isCustomColor) {
                updateWatermarkLayer()
            }
        }
        .onAppear {
            loadLEDFont()
        }
        .onDisappear {
            // 关闭字体面板
            NSFontPanel.shared.orderOut(nil)
        }
        .alert("处理完成".localized, isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("不支持的格式", isPresented: Binding(
            get: { !unsupportedFormats.isEmpty },
            set: { if !$0 { unsupportedFormats.removeAll() } }
        )) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("以下格式的照片不受支持：\n\(unsupportedFormats.joined(separator: "\n"))")
        }
        .sheet(isPresented: $showDateFormatPicker) {
            VStack(spacing: 20) {
                Text("自定义日期格式".localized)
                    .font(.headline)
                    .padding(.top)
                
                TextField("输入日期格式", text: $dateFormat)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Text("格式说明：\nyyyy - 年份\nMM - 月份\ndd - 日期")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                HStack(spacing: 20) {
                    Button("取消") {
                        showDateFormatPicker = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("确定") {
                        isCustomDateFormat = true
                        showDateFormatPicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom)
            }
            .frame(width: 300, height: 200)
        }
        // 监听预览索引变化
        .onChange(of: selectedPreviewIndex) { _ in
            loadOriginalImage()
        }
    }
    
    private func loadLEDFont() {
        if let fontURL = Bundle.main.url(forResource: "led-digital-7-1", withExtension: "ttf") {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                defaultFontLoaded = true
                ledFont = NSFont(name: "LED Digital 7", size: 24) ?? NSFont.systemFont(ofSize: 24)
            } else {
                print("字体加载失败: \(error.debugDescription)")
                defaultFontLoaded = false
            }
        } else {
            print("找不到字体文件")
            defaultFontLoaded = false
        }
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .folder]
        
        panel.begin { response in
            if response == .OK {
                // 创建新的选择数组
                var newSelection: [URL] = []
                
                for url in panel.urls {
                    if url.hasDirectoryPath {
                        // 处理文件夹
                        processDirectory(url, newSelection: &newSelection)
                    } else {
                        // 处理单个文件
                        let pathExtension = url.pathExtension.lowercased()
                        if supportedImageExtensions.contains(pathExtension) {
                            newSelection.append(url)
                        }
                    }
                }
                
                // 更新选择
                selectedImages = newSelection
            }
        }
    }
    
    // 修改预览加载函数
    private func loadOriginalImage() {
        guard !selectedImages.isEmpty else {
            originalPreviewImage = nil
            watermarkLayer = nil
            return
        }
        
        Task { @MainActor in
            isLoadingImage = true
        }
        
        Task.detached(priority: .userInitiated) {
            let imageURL = selectedImages[selectedPreviewIndex]
            
            // 在后台线程加载 HEIC 图片
            let image: NSImage?
            let fileExtension = imageURL.pathExtension.lowercased()
            
            if fileExtension == "heic" {
                // 对 HEIC 格式使用 ImageIO
                guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
                else {
                    await MainActor.run {
                        isLoadingImage = false
                    }
                    return
                }
                
                let size = CGSize(
                    width: cgImage.width,
                    height: cgImage.height
                )
                
                let nsImage = NSImage(size: size)
                nsImage.lockFocus()
                if let context = NSGraphicsContext.current?.cgContext {
                    context.draw(cgImage, in: CGRect(origin: .zero, size: size))
                }
                nsImage.unlockFocus()
                image = nsImage
            } else {
                // 其他格式直接使用 NSImage
                image = NSImage(contentsOf: imageURL)
            }
            
            // 在主线程更新 UI
            await MainActor.run {
                if let loadedImage = image {
                    originalPreviewImage = loadedImage
                    updateWatermarkLayer()
                }
                isLoadingImage = false
            }
        }
    }
    
    // 更新水印层
    private func updateWatermarkLayer() {
        guard let originalImage = originalPreviewImage else { return }
        
        isRefreshingWatermark = true
        let imageSize = originalImage.size
        
        Task {
            // 获取当前预览图片的创建时间
            let imageURL = selectedImages[selectedPreviewIndex]
            let photoDate = getPhotoCreationDate(from: imageURL) ?? Date()
            let dateString = dateFormatter.string(from: photoDate)
            
            // 在主线程创建和更新水印层
            await MainActor.run {
                // 创建新的水印层
                let layer = NSImage(size: imageSize)
                layer.lockFocus()
                
                // 确保背景透明
                NSColor.clear.set()
                NSRect(origin: .zero, size: imageSize).fill()
                
                // 计算自适应大小
                let adaptiveFontSize = calculateAdaptiveFontSize(for: imageSize, fontSize: selectedFontSize)
                let adaptiveMargin = calculateAdaptiveMargin(for: imageSize)
                
                // 设置字体和颜色
                let fixedFont = NSFontManager.shared.convert(ledFont, toSize: adaptiveFontSize)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: fixedFont,
                    .foregroundColor: selectedColor
                ]
                
                // 创建并绘制文字
                let attributedString = NSAttributedString(string: dateString, attributes: attributes)
                let stringSize = attributedString.size()
                
                attributedString.draw(at: NSPoint(
                    x: imageSize.width - stringSize.width - adaptiveMargin,
                    y: adaptiveMargin
                ))
                
                layer.unlockFocus()
                watermarkLayer = layer
            }
            
            // 在主线程更新UI
            await MainActor.run {
                isRefreshingWatermark = false
            }
        }
    }
    
    // 添加进度管理器
    private actor ProcessingProgress {
        private(set) var completed: Int = 0
        private(set) var processing: Int = 0
        private var total: Int
        
        init(total: Int) {
            self.total = total
        }
        
        func incrementCompleted() -> (completed: Int, progress: Double) {
            completed += 1
            return (completed, Double(completed) / Double(total))
        }
        
        func incrementProcessing() {
            processing += 1
        }
        
        func decrementProcessing() {
            processing -= 1
        }
        
        var isProcessingFull: Bool {
            processing >= 4 // 最大并发数
        }
    }
    
    // 修改处理函数
    private func processImages() {
        guard !selectedImages.isEmpty else { return }
        
        Task { @MainActor in
            isProcessing = true
            processProgress = 0
            processedCount = 0
            
            let panel = NSSavePanel()
            panel.title = "选择保存位置".localized
            panel.canCreateDirectories = true
            panel.canSelectHiddenExtension = true
            panel.prompt = "选择".localized
            panel.nameFieldStringValue = "未命名".localized
            
            let response = await panel.beginSheetModal(for: NSApp.keyWindow!)
            let saveURL = response == .OK ? panel.url : nil
            
            if let saveURL = saveURL {
                currentTask = Task {
                    do {
                        let processParams = ProcessParams(
                            dateString: dateFormatter.string(from: Date()),
                            color: selectedColor,
                            font: ledFont,
                            fontSize: selectedFontSize,
                            outputDir: saveURL
                        )
                        
                        let progress = ProcessingProgress(total: selectedImages.count)
                        
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            for imageURL in selectedImages {
                                try Task.checkCancellation()
                                
                                while await progress.isProcessingFull {
                                    try await Task.sleep(nanoseconds: 100_000_000)
                                }
                                
                                await progress.incrementProcessing()
                                
                                group.addTask {
                                    try Task.checkCancellation()
                                    
                                    await MainActor.run {
                                        currentProcessingFile = imageURL.lastPathComponent
                                    }
                                    
                                    try await processImage(imageURL, with: processParams)
                                    
                                    // 获取进度信息
                                    let (completed, newProgress) = await progress.incrementCompleted()
                                    await progress.decrementProcessing()
                                    
                                    // 更新UI
                                    await MainActor.run {
                                        processedCount = completed
                                        processProgress = newProgress
                                    }
                                }
                            }
                            
                            try await group.waitForAll()
                        }
                        
                        // 在主线程显示完成提示
                        await MainActor.run {
                            if let window = NSApp.keyWindow {
                                let alert = NSAlert()
                                alert.messageText = "处理完成".localized
                                alert.informativeText = "已成功处理 %d 张图片\n保存位置：%@".localizedFormat(selectedImages.count, saveURL.path)
                                alert.alertStyle = .informational
                                alert.addButton(withTitle: "确定".localized)
                                alert.addButton(withTitle: "打开文件夹".localized)
                                
                                let response = showCenteredAlert(alert, relativeTo: window)
                                if response == .alertSecondButtonReturn {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: saveURL.path)
                                }
                            }
                        }
                        
                    } catch is CancellationError {
                        print("Task was cancelled")
                    } catch {
                        await MainActor.run {
                            if let window = NSApp.keyWindow {
                                let alert = NSAlert()
                                alert.messageText = "处理出错".localized
                                alert.informativeText = error.localizedDescription
                                alert.alertStyle = .warning
                                alert.addButton(withTitle: "确定".localized)
                                
                                _ = showCenteredAlert(alert, relativeTo: window)
                            }
                        }
                    }
                    
                    await MainActor.run {
                        isProcessing = false
                        processedCount = 0
                        currentProcessingFile = ""
                        currentTask = nil
                    }
                }
            } else {
                isProcessing = false
                currentTask = nil
            }
        }
    }
    
    // 处理参数结构体
    private struct ProcessParams {
        let dateString: String
        let color: NSColor
        let font: NSFont
        let fontSize: FontSize
        let outputDir: URL
    }
    
    // 获取照片创建时间的函数
    private func getPhotoCreationDate(from imageURL: URL) -> Date? {
        if let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            // 尝试从 EXIF 获取创建时间
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let dateTimeOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                return formatter.date(from: dateTimeOriginal)
            }
            
            // 尝试从 TIFF 获取创建时间
            if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let dateTime = tiff[kCGImagePropertyTIFFDateTime] as? String {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                return formatter.date(from: dateTime)
            }
        }
        return nil
    }
    
    // 修改处理图片函数
    private func processImage(_ imageURL: URL, with params: ProcessParams) async throws {
        let fileExtension = imageURL.pathExtension.lowercased()
        let image: NSImage
        
        // 获取照片创建时间
        let photoDate = getPhotoCreationDate(from: imageURL) ?? Date()
        let dateString = dateFormatter.string(from: photoDate)
        
        if fileExtension == "heic" {
            // 在后台线程加载 HEIC 图片
            guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            else {
                throw NSError(
                    domain: "WatermarkPlus",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "无法加载HEIC图片：%@".localizedFormat(imageURL.lastPathComponent)]
                )
            }
            
            let size = CGSize(
                width: cgImage.width,
                height: cgImage.height
            )
            
            let nsImage = NSImage(size: size)
            nsImage.lockFocus()
            if let context = NSGraphicsContext.current?.cgContext {
                context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            }
            nsImage.unlockFocus()
            image = nsImage
        } else {
            // 其他格式直接使用 NSImage
            guard let loadedImage = NSImage(contentsOf: imageURL) else {
                throw NSError(
                    domain: "WatermarkPlus",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "无法加载图片：%@".localizedFormat(imageURL.lastPathComponent)]
                )
            }
            image = loadedImage
        }
        
        let imageSize = image.size
        
        // 创建新图像并添加水印
        let newImage = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            // 获取原始图片的像素尺寸
            let originalSize: CGSize
            if let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                let width = properties[kCGImagePropertyPixelWidth] as? Int ?? Int(imageSize.width)
                let height = properties[kCGImagePropertyPixelHeight] as? Int ?? Int(imageSize.height)
                originalSize = CGSize(width: width, height: height)
            } else {
                originalSize = imageSize
            }
            
            // 创建位图表示
            let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(originalSize.width),
                pixelsHigh: Int(originalSize.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
            
            guard let bitmapRep = bitmapRep else { return nil }
            
            // 创建新的 NSImage
            let result = NSImage(size: originalSize)
            result.addRepresentation(bitmapRep)
            
            // 开始绘制
            result.lockFocus()
            
            // 设置绘制上下文
            if let context = NSGraphicsContext.current?.cgContext {
                // 设置高质量渲染
                context.setShouldAntialias(true)
                context.setAllowsAntialiasing(true)
                context.setShouldSmoothFonts(true)
                context.setAllowsFontSmoothing(true)
                
                // 绘制原始图像
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    context.draw(cgImage, in: CGRect(origin: .zero, size: originalSize))
                }
                
                // 计算自适应大小，基于原始尺寸
                let adaptiveFontSize = calculateAdaptiveFontSize(for: originalSize, fontSize: params.fontSize)
                let adaptiveMargin = calculateAdaptiveMargin(for: originalSize)
                
                // 设置字体和颜色
                let fixedFont = NSFontManager.shared.convert(params.font, toSize: adaptiveFontSize)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: fixedFont,
                    .foregroundColor: params.color
                ]
                
                // 创建并绘制文字
                let attributedString = NSAttributedString(string: params.dateString, attributes: attributes)
                let stringSize = attributedString.size()
                
                attributedString.draw(at: NSPoint(
                    x: originalSize.width - stringSize.width - adaptiveMargin,
                    y: adaptiveMargin
                ))
            }
            
            result.unlockFocus()
            return result
        }.value
        
        // 保存图像
        if let newImage = newImage {
            try await Task.detached(priority: .userInitiated) {
                let fileName = imageURL.lastPathComponent
                let saveURL = params.outputDir.appendingPathComponent(fileName)
                
                if !FileManager.default.fileExists(atPath: params.outputDir.path) {
                    try FileManager.default.createDirectory(
                        atPath: params.outputDir.path,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                }
                
                // 获取原始图片的像素尺寸
                let originalSize: CGSize
                if let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                   let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                    let width = properties[kCGImagePropertyPixelWidth] as? Int ?? Int(imageSize.width)
                    let height = properties[kCGImagePropertyPixelHeight] as? Int ?? Int(imageSize.height)
                    originalSize = CGSize(width: width, height: height)
                } else {
                    originalSize = imageSize
                }
                
                switch fileExtension.lowercased() {
                case "heic":
                    // 对于 HEIC 格式，使用 ImageIO 框架并保持原始分辨率
                    if let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        guard let destination = CGImageDestinationCreateWithURL(
                            saveURL as CFURL,
                            UTType.heic.identifier as CFString,
                            1,
                            nil
                        ) else { return }
                        
                        // 获取原始图片的属性
                        guard let sourceImageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                              let properties = CGImageSourceCopyPropertiesAtIndex(sourceImageSource, 0, nil) as? [CFString: Any]
                        else { return }
                        
                        // 获取原始 HEIC 图片的具体尺寸
                        let originalWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? cgImage.width
                        let originalHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? cgImage.height
                        
                        // 设置输出选项
                        let options: [CFString: Any] = [
                            kCGImageDestinationLossyCompressionQuality: 0.85,
                            kCGImagePropertyOrientation: properties[kCGImagePropertyOrientation] ?? 1,
                            kCGImageDestinationImageMaxPixelSize: max(originalWidth, originalHeight),
                            kCGImagePropertyPixelWidth: originalWidth,
                            kCGImagePropertyPixelHeight: originalHeight,
                            kCGImagePropertyDPIWidth: properties[kCGImagePropertyDPIWidth] ?? 72,
                            kCGImagePropertyDPIHeight: properties[kCGImagePropertyDPIHeight] ?? 72,
                            kCGImageDestinationOptimizeColorForSharing: false,
                            kCGImagePropertyColorModel: properties[kCGImagePropertyColorModel] ?? kCGImagePropertyColorModelRGB
                        ]
                        
                        // 创建一个与原始尺寸相同的图像上下文
                        let context = CGContext(
                            data: nil,
                            width: originalWidth,
                            height: originalHeight,
                            bitsPerComponent: 8,
                            bytesPerRow: 0,
                            space: cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        )
                        
                        if let context = context {
                            // 在正确的尺寸上绘制图像
                            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight))
                            
                            if let finalImage = context.makeImage() {
                                CGImageDestinationAddImage(destination, finalImage, options as CFDictionary)
                                
                                if !CGImageDestinationFinalize(destination) {
                                    print("Failed to finalize HEIC image")
                                }
                            }
                        }
                    }
                    
                case "png":
                    // 设置 PNG 输出选项
                    let pngProperties: [NSBitmapImageRep.PropertyKey: Any] = [
                        .compressionFactor: 1.0,
                        .interlaced: false
                    ]
                    
                    // 添加调试信息
                    print("PNG 输出调试信息:")
                    print("原始图片尺寸: \(imageSize)")
                    print("目标像素尺寸: \(originalSize)")
                    
                    // 创建新的位图表示，直接指定像素尺寸
                    if let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let bitmapRep = NSBitmapImageRep(
                            bitmapDataPlanes: nil,
                            pixelsWide: Int(originalSize.width),
                            pixelsHigh: Int(originalSize.height),
                            bitsPerSample: 8,
                            samplesPerPixel: 4,
                            hasAlpha: true,
                            isPlanar: false,
                            colorSpaceName: .deviceRGB,
                            bytesPerRow: 0,
                            bitsPerPixel: 0
                        )
                        
                        if let bitmapRep = bitmapRep {
                            // 添加位图表示创建后的调试信息
                            print("位图表示实际尺寸: \(bitmapRep.size)")
                            print("位图表示像素尺寸: \(bitmapRep.pixelsWide)x\(bitmapRep.pixelsHigh)")
                            
                            // 直接在位图表示上绘制
                            if let context = NSGraphicsContext(bitmapImageRep: bitmapRep) {
                                NSGraphicsContext.saveGraphicsState()
                                NSGraphicsContext.current = context
                                
                                // 设置高质量渲染
                                context.cgContext.setShouldAntialias(true)
                                context.cgContext.setAllowsAntialiasing(true)
                                context.cgContext.setShouldSmoothFonts(true)
                                context.cgContext.setAllowsFontSmoothing(true)
                                
                                // 绘制图像
                                context.cgContext.draw(cgImage, in: CGRect(origin: .zero, size: originalSize))
                                
                                NSGraphicsContext.restoreGraphicsState()
                            }
                            
                            try bitmapRep.representation(using: .png, properties: pngProperties)?.write(to: saveURL)
                            
                            // 添加保存后的调试信息
                            print("文件已保存到: \(saveURL.path)")
                        }
                    }
                    
                case "jpg", "jpeg":
                    // 设置 JPEG 输出选项
                    let jpegProperties: [NSBitmapImageRep.PropertyKey: Any] = [
                        .compressionFactor: 0.85,
                        .interlaced: false
                    ]
                    
                    // 添加调试信息
                    print("JPEG 输出调试信息:")
                    print("原始图片尺寸: \(imageSize)")
                    print("目标像素尺寸: \(originalSize)")
                    
                    // 创建新的位图表示，直接指定像素尺寸
                    if let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let bitmapRep = NSBitmapImageRep(
                            bitmapDataPlanes: nil,
                            pixelsWide: Int(originalSize.width),
                            pixelsHigh: Int(originalSize.height),
                            bitsPerSample: 8,
                            samplesPerPixel: 4,
                            hasAlpha: true,
                            isPlanar: false,
                            colorSpaceName: .deviceRGB,
                            bytesPerRow: 0,
                            bitsPerPixel: 0
                        )
                        
                        if let bitmapRep = bitmapRep {
                            // 添加位图表示创建后的调试信息
                            print("位图表示实际尺寸: \(bitmapRep.size)")
                            print("位图表示像素尺寸: \(bitmapRep.pixelsWide)x\(bitmapRep.pixelsHigh)")
                            
                            // 直接在位图表示上绘制
                            if let context = NSGraphicsContext(bitmapImageRep: bitmapRep) {
                                NSGraphicsContext.saveGraphicsState()
                                NSGraphicsContext.current = context
                                
                                // 设置高质量渲染
                                context.cgContext.setShouldAntialias(true)
                                context.cgContext.setAllowsAntialiasing(true)
                                context.cgContext.setShouldSmoothFonts(true)
                                context.cgContext.setAllowsFontSmoothing(true)
                                
                                // 绘制图像
                                context.cgContext.draw(cgImage, in: CGRect(origin: .zero, size: originalSize))
                                
                                NSGraphicsContext.restoreGraphicsState()
                            }
                            
                            try bitmapRep.representation(using: .jpeg, properties: jpegProperties)?.write(to: saveURL)
                            
                            // 添加保存后的调试信息
                            print("文件已保存到: \(saveURL.path)")
                        }
                    }
                    
                case "tiff":
                    // 设置 TIFF 输出选项
                    let tiffProperties: [NSBitmapImageRep.PropertyKey: Any] = [
                        .compressionMethod: NSBitmapImageRep.TIFFCompression.lzw,
                        .interlaced: false
                    ]
                    
                    // 创建新的位图表示，直接指定像素尺寸
                    if let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let bitmapRep = NSBitmapImageRep(
                            bitmapDataPlanes: nil,
                            pixelsWide: Int(originalSize.width),
                            pixelsHigh: Int(originalSize.height),
                            bitsPerSample: 8,
                            samplesPerPixel: 4,
                            hasAlpha: true,
                            isPlanar: false,
                            colorSpaceName: .deviceRGB,
                            bytesPerRow: 0,
                            bitsPerPixel: 0
                        )
                        
                        if let bitmapRep = bitmapRep {
                            // 创建临时图像用于绘制
                            let tempImage = NSImage(size: originalSize)
                            tempImage.addRepresentation(bitmapRep)
                            
                            // 绘制到临时图像
                            tempImage.lockFocus()
                            if let context = NSGraphicsContext.current?.cgContext {
                                context.draw(cgImage, in: CGRect(origin: .zero, size: originalSize))
                            }
                            tempImage.unlockFocus()
                            
                            try bitmapRep.representation(using: .tiff, properties: tiffProperties)?.write(to: saveURL)
                        }
                    }
                    
                case "gif":
                    // 添加调试信息
                    print("GIF 输出调试信息:")
                    print("原始图片尺寸: \(imageSize)")
                    print("目标像素尺寸: \(originalSize)")
                    
                    // 使用 ImageIO 处理 GIF
                    if let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil) {
                        let frameCount = CGImageSourceGetCount(imageSource)
                        print("GIF 帧数: \(frameCount)")
                        
                        // 创建目标
                        guard let destination = CGImageDestinationCreateWithURL(
                            saveURL as CFURL,
                            UTType.gif.identifier as CFString,
                            frameCount,
                            nil
                        ) else {
                            print("无法创建 GIF 目标")
                            return
                        }
                        
                        // 获取原始 GIF 的属性
                        let sourceProperties = CGImageSourceCopyProperties(imageSource, nil) as? [CFString: Any]
                        let gifProperties = sourceProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                        
                        // 设置 GIF 属性
                        let destinationProperties: [CFString: Any] = [
                            kCGImagePropertyGIFDictionary: [
                                kCGImagePropertyGIFLoopCount: gifProperties?[kCGImagePropertyGIFLoopCount] ?? 0,
                                kCGImagePropertyGIFDelayTime: gifProperties?[kCGImagePropertyGIFDelayTime] ?? 0.1
                            ]
                        ]
                        
                        CGImageDestinationSetProperties(destination, destinationProperties as CFDictionary)
                        
                        // 处理每一帧
                        for index in 0..<frameCount {
                            // 获取原始帧
                            guard let originalFrame = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else {
                                print("无法获取第 \(index) 帧")
                                continue
                            }
                            
                            // 创建位图表示
                            let bitmapRep = NSBitmapImageRep(
                                bitmapDataPlanes: nil,
                                pixelsWide: Int(originalSize.width),
                                pixelsHigh: Int(originalSize.height),
                                bitsPerSample: 8,
                                samplesPerPixel: 4,
                                hasAlpha: true,
                                isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: 0,
                                bitsPerPixel: 0
                            )
                            
                            guard let bitmapRep = bitmapRep else {
                                print("无法创建位图表示")
                                continue
                            }
                            
                            // 直接在位图表示上绘制
                            if let context = NSGraphicsContext(bitmapImageRep: bitmapRep) {
                                NSGraphicsContext.saveGraphicsState()
                                NSGraphicsContext.current = context
                                
                                // 设置高质量渲染
                                context.cgContext.setShouldAntialias(true)
                                context.cgContext.setAllowsAntialiasing(true)
                                context.cgContext.setShouldSmoothFonts(true)
                                context.cgContext.setAllowsFontSmoothing(true)
                                
                                // 绘制原始帧
                                context.cgContext.draw(originalFrame, in: CGRect(origin: .zero, size: originalSize))
                                
                                // 获取帧属性
                                let frameProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any]
                                let gifFrameProperties = frameProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                                
                                // 计算自适应大小
                                let adaptiveFontSize = calculateAdaptiveFontSize(for: originalSize, fontSize: params.fontSize)
                                let adaptiveMargin = calculateAdaptiveMargin(for: originalSize)
                                
                                // 设置字体和颜色
                                let fixedFont = NSFontManager.shared.convert(params.font, toSize: adaptiveFontSize)
                                let attributes: [NSAttributedString.Key: Any] = [
                                    .font: fixedFont,
                                    .foregroundColor: params.color
                                ]
                                
                                // 创建并绘制文字
                                let attributedString = NSAttributedString(string: params.dateString, attributes: attributes)
                                let stringSize = attributedString.size()
                                
                                attributedString.draw(at: NSPoint(
                                    x: originalSize.width - stringSize.width - adaptiveMargin,
                                    y: adaptiveMargin
                                ))
                                
                                NSGraphicsContext.restoreGraphicsState()
                                
                                // 获取处理后的帧
                                if let processedFrame = bitmapRep.cgImage {
                                    // 设置帧属性
                                    let frameDestinationProperties: [CFString: Any] = [
                                        kCGImagePropertyGIFDictionary: [
                                            kCGImagePropertyGIFDelayTime: gifFrameProperties?[kCGImagePropertyGIFDelayTime] ?? 0.1,
                                            kCGImagePropertyGIFUnclampedDelayTime: gifFrameProperties?[kCGImagePropertyGIFUnclampedDelayTime] ?? 0.1
                                        ]
                                    ]
                                    
                                    // 添加帧到目标
                                    CGImageDestinationAddImage(destination, processedFrame, frameDestinationProperties as CFDictionary)
                                }
                            }
                        }
                        
                        // 完成 GIF 创建
                        if !CGImageDestinationFinalize(destination) {
                            print("无法完成 GIF 创建")
                        } else {
                            print("GIF 已成功保存到: \(saveURL.path)")
                        }
                    }
                    
                default:
                    // 默认使用 JPEG 格式
                    let jpegProperties: [NSBitmapImageRep.PropertyKey: Any] = [
                        .compressionFactor: 0.85,
                        .interlaced: false
                    ]
                    
                    // 创建新的位图表示，直接指定像素尺寸
                    if let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let bitmapRep = NSBitmapImageRep(
                            bitmapDataPlanes: nil,
                            pixelsWide: Int(originalSize.width),
                            pixelsHigh: Int(originalSize.height),
                            bitsPerSample: 8,
                            samplesPerPixel: 4,
                            hasAlpha: true,
                            isPlanar: false,
                            colorSpaceName: .deviceRGB,
                            bytesPerRow: 0,
                            bitsPerPixel: 0
                        )
                        
                        if let bitmapRep = bitmapRep {
                            // 创建临时图像用于绘制
                            let tempImage = NSImage(size: originalSize)
                            tempImage.addRepresentation(bitmapRep)
                            
                            // 绘制到临时图像
                            tempImage.lockFocus()
                            if let context = NSGraphicsContext.current?.cgContext {
                                context.draw(cgImage, in: CGRect(origin: .zero, size: originalSize))
                            }
                            tempImage.unlockFocus()
                            
                            try bitmapRep.representation(using: .jpeg, properties: jpegProperties)?.write(to: saveURL)
                        }
                    }
                }
            }.value
        }
    }
    
    // 更新处理按钮显示进度
    private var processButtonContent: some View {
        HStack {
            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .controlSize(.small)
                    VStack(alignment: .center, spacing: 2) {
                        Text("处理中...".localizedFormat(Int(processProgress * 100)))
                        Text(currentProcessingFile)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("开始处理".localized)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 36)
    }
    
    // 计算自适应字体大小的函数
    private func calculateAdaptiveFontSize(for imageSize: CGSize, fontSize: FontSize) -> CGFloat {
        // 使用图片对角线长度作为参考
        let diagonalLength = sqrt(pow(imageSize.width, 2) + pow(imageSize.height, 2))
        // 根据选择的大小计算字体大小
        let adaptiveFontSize = diagonalLength * fontSize.scaleFactor
        
        // 限制最小和最大字体大小
        let minFontSize: CGFloat = 16
        let maxFontSize: CGFloat = 200
        
        return min(max(adaptiveFontSize, minFontSize), maxFontSize)
    }
    
    // 添加计算边距的函数
    private func calculateAdaptiveMargin(for imageSize: CGSize) -> CGFloat {
        // 使用图片较短边的长度作为参考
        let shortestSide = min(imageSize.width, imageSize.height)
        // 边距设置为较短边的 3%
        let adaptiveMargin = shortestSide * 0.03
        
        // 设置最小和最大边距限制
        let minMargin: CGFloat = 20
        let maxMargin: CGFloat = 100
        
        return min(max(adaptiveMargin, minMargin), maxMargin)
    }
    
    // 生成预览图片的函数
    private func generatePreview() {
        guard !selectedImages.isEmpty else {
            previewImage = nil
            return
        }
        
        // 标记正在生成预览
        isGeneratingPreview = true
        
        Task {
            let imageURL = selectedImages[selectedPreviewIndex]
            
            // 在后台线程处理图片
            let preview = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let image = NSImage(contentsOf: imageURL) else { return nil }
                let imageSize = image.size
                
                // 创建预览图像
                let preview = NSImage(size: imageSize)
                
                return await withCheckedContinuation { continuation in
                        DispatchQueue.main.async {
                        preview.lockFocus()
                        
                        // 绘制原始图像
                        image.draw(in: NSRect(origin: .zero, size: imageSize))
                        
                        // 获取日期字符串
                        let dateString = dateFormatter.string(from: Date())
                        
                        // 计算自适应大小
                        let adaptiveFontSize = calculateAdaptiveFontSize(for: imageSize, fontSize: selectedFontSize)
                        let adaptiveMargin = calculateAdaptiveMargin(for: imageSize)
                        
                        // 设置字体和颜色
                        let fixedFont = NSFontManager.shared.convert(selectedFont, toSize: adaptiveFontSize)
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: fixedFont,
                            .foregroundColor: selectedColor
                        ]
                        
                        // 创建并绘制文字
                        let attributedString = NSAttributedString(string: dateString, attributes: attributes)
                        let stringSize = attributedString.size()
                        
                        attributedString.draw(at: NSPoint(
                            x: imageSize.width - stringSize.width - adaptiveMargin,
                            y: adaptiveMargin
                        ))
                        
                        preview.unlockFocus()
                        
                        continuation.resume(returning: preview)
                    }
                }
            }.value
                    
                    // 在主线程更新 UI
            await MainActor.run {
                previewImage = preview
                isGeneratingPreview = false
            }
        }
    }
}

// NSFontPickerView 包装器
struct NSFontPickerView: NSViewRepresentable {
    @Binding var selectedFont: NSFont
    
    class FontPickerViewController: NSViewController {
        var onFontChange: ((NSFont) -> Void)?
        var currentFont: NSFont = NSFont.systemFont(ofSize: 14)
        
        override func loadView() {
            self.view = NSView()
        }
        
        override func viewDidLoad() {
            super.viewDidLoad()
            NSFontManager.shared.target = self
            NSFontManager.shared.action = #selector(changeFont(_:))
        }
        
        @objc func changeFont(_ sender: NSFontManager?) {
            guard let fontManager = sender else { return }
            currentFont = fontManager.convert(currentFont)
            onFontChange?(currentFont)
        }
    }
    
    func makeNSView(context: Context) -> NSView {
        let viewController = FontPickerViewController()
        viewController.currentFont = selectedFont
        viewController.onFontChange = { font in
            selectedFont = font
        }
        return viewController.view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 更新不需要特殊处理
    }
}

// 字体选择器视图
struct FontPickerView: View {
    @Binding var selectedFont: NSFont
    @Binding var isCustomFont: Bool
    var onFontSelected: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("选择字体".localized)
                .font(.headline)
            
            // 显示当前选择的字体名称
            Text(selectedFont.displayName ?? "未选择字体".localized)
                .font(.system(size: 16))
            
            // 预览区域
            Text("预览文字".localized)
                .font(Font(selectedFont))
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
            
            // 字体选择按钮
            Button("打开字体选择器".localized) {
                NSFontPanel.shared.setPanelFont(selectedFont, isMultiple: false)
                NSFontPanel.shared.orderFront(nil)
            }
            .padding()
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 20) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("确定") {
                    isCustomFont = true
                    onFontSelected()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
        .background(NSFontPickerView(selectedFont: $selectedFont).opacity(0.1))
    }
}

// 颜色选择器视图
struct ColorPickerView: View {
    @Binding var selectedColor: NSColor
    @Binding var isCustomColor: Bool
    var onColorSelected: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            ColorPicker("选择颜色".localized, selection: Binding(
                get: { Color(nsColor: selectedColor) },
                set: { selectedColor = NSColor($0) }
            ))
            .padding()
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                Button("确定") {
                    isCustomColor = true
                    onColorSelected()
                    dismiss()
                }
            }
            .padding()
        }
        .frame(width: 300)
        .padding()
    }
}

// 添加辅助扩展
extension NSBitmapImageRep.FileType {
    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "jpg", "jpeg":
            self = .jpeg
        case "png":
            self = .png
        case "gif":
            self = .gif
        case "tiff":
            self = .tiff
        case "bmp":
            self = .bmp
        default:
            return nil
        }
    }
}

#Preview {
    ContentView()
}

