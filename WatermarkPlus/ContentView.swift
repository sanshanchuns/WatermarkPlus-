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
    
    // 定义可聚焦的字段枚举
    enum Field {
        case processButton
        case alertButton
    }
    
    // 预设日期格式
    private let presetDateFormats: [(name: String, format: String)] = [
        ("标准", "yyyy-MM-dd"),
        ("简洁", "yy.MM.dd"),
        ("斜杠", "yyyy/MM/dd"),
        ("点号", "yyyy.MM.dd")
    ]
    
    // 预设颜色（高饱和度）
    private let presetColors: [(name: String, color: NSColor)] = [
        ("柯达黄", NSColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)),    // 柯达胶卷经典黄
        ("天蓝", NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)),   // 纯净的蓝色
        ("翠绿", NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)),   // 鲜艳的绿色
        ("明黄", NSColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0)),   // 明亮的黄色
        ("玫红", NSColor(red: 1.0, green: 0.2, blue: 0.6, alpha: 1.0))    // 鲜艳的玫红色
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
                            Text("拖放照片或文件夹到这里\n或点击选择")
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
                .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
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
                        selectedImages = newSelection
                    }
                    
                    return true
                }
                
                // 状态信息区域
                VStack(spacing: 5) {
                    if !selectedImages.isEmpty {
                        Text("已选择 \(selectedImages.count) 张照片")
                            .font(.headline)
                    } else {
                        Text("")
                            .font(.headline)
                            .frame(height: 20)
                    }
                    
                    if isProcessing {
                        ProgressView("正在处理...", value: Double(processedCount), total: Double(selectedImages.count))
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
                        Text("日期格式")
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
                    
                    // 颜色选择
                    VStack(alignment: .leading) {
                        Text("水印颜色")
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
                            
                            Button(action: {
                                showColorPicker = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 24))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    // 处理按钮
                    Button(action: {
                        processImages()
                    }) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 5)
                            }
                            Text(isProcessing ? "处理中..." : "开始处理")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedImages.isEmpty || isProcessing)
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
                generatePreview()
            }
        }
        .onAppear {
            loadLEDFont()
        }
        .onDisappear {
            // 关闭字体面板
            NSFontPanel.shared.orderOut(nil)
        }
        .alert("处理完成", isPresented: $showAlert) {
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
                Text("自定义日期格式")
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
    
    // 在后台线程加载和转换图片
    private func loadImageInBackground(_ url: URL) async -> NSImage? {
        return await Task.detached(priority: .userInitiated) { () -> NSImage? in
            // 对于 HEIC 格式，使用 CGImageSource 处理
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
            
            // 创建 NSImage
            let size = NSSize(
                width: cgImage.width,
                height: cgImage.height
            )
            
            let nsImage = NSImage(size: size)
            nsImage.lockFocus()
            
            let context = NSGraphicsContext.current?.cgContext
            // 直接绘制，不需要翻转坐标系
            context?.draw(cgImage, in: CGRect(origin: .zero, size: size))
            
            nsImage.unlockFocus()
            return nsImage
        }.value
    }
    
    // 加载原始图片
    private func loadOriginalImage() {
        guard !selectedImages.isEmpty else {
            originalPreviewImage = nil
            watermarkLayer = nil
            return
        }
        
        isLoadingImage = true
        
        Task {
            let imageURL = selectedImages[selectedPreviewIndex]
            
            // 在后台线程加载和处理图片
            if let image = await loadImageInBackground(imageURL) {
                await MainActor.run {
                    originalPreviewImage = image
                    isLoadingImage = false
                    updateWatermarkLayer()
                }
            }
        }
    }
    
    // 更新水印层
    private func updateWatermarkLayer() {
        guard let originalImage = originalPreviewImage else { return }
        
        isRefreshingWatermark = true
        let imageSize = originalImage.size
        
        Task {
            // 在后台线程准备水印数据
            let watermarkData = await Task.detached(priority: .userInitiated) { () -> Data? in
                // 创建位图表示
                let bitmapRep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(imageSize.width),
                    pixelsHigh: Int(imageSize.height),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                )
                
                // 准备绘制属性
                let dateString = dateFormatter.string(from: Date())
                let adaptiveFontSize = calculateAdaptiveFontSize(for: imageSize)
                let adaptiveMargin = calculateAdaptiveMargin(for: imageSize)
                
                // 在主线程执行绘制操作
                await MainActor.run {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep!)
                    
                    // 确保背景透明
                    NSColor.clear.set()
                    NSRect(origin: .zero, size: imageSize).fill()
                    
                    // 设置字体和颜色
                    let fixedFont = NSFontManager.shared.convert(defaultFont, toSize: adaptiveFontSize)
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
                    
                    NSGraphicsContext.restoreGraphicsState()
                }
                
                // 在后台线程处理图片数据
                return bitmapRep?.representation(using: .png, properties: [:])
            }.value
            
            // 在主线程更新UI
            await MainActor.run {
                if let watermarkData = watermarkData {
                    watermarkLayer = NSImage(data: watermarkData)
                }
                isRefreshingWatermark = false
            }
        }
    }
    
    private func processImages() {
        guard !selectedImages.isEmpty else { return }
        
        isProcessing = true
        processedCount = 0
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.folder]
        savePanel.nameFieldStringValue = "watermarked_images"
        
        if savePanel.runModal() == .OK {
            if let saveURL = savePanel.url {
                let fileManager = FileManager.default
                let imagesToProcess = selectedImages // 创建副本
                
                // 创建保存目录
                do {
                    try fileManager.createDirectory(at: saveURL, withIntermediateDirectories: true)
                } catch {
                    DispatchQueue.main.async {
                        alertMessage = "创建保存目录失败：\(error.localizedDescription)"
                        showAlert = true
                        isProcessing = false
                    }
                    return
                }
                
                // 在后台线程处理图片
                DispatchQueue.global(qos: .userInitiated).async {
                    var successCount = 0
                    var failedCount = 0
                    
                    // 创建处理图片用的属性副本
                    let currentFont = defaultFont
                    let currentColor = selectedColor
                    let currentDateFormatter = dateFormatter
                    
                    for imageURL in imagesToProcess {
                        if let image = NSImage(contentsOf: imageURL) {
                            let imageSize = image.size
                            // 计算适应的字体大小
                            let adaptiveFontSize = calculateAdaptiveFontSize(for: imageSize)
                            let fixedFont = NSFontManager.shared.convert(currentFont, toSize: adaptiveFontSize)
                            
                            // 获取照片的创建时间
                            if let resourceValues = try? imageURL.resourceValues(forKeys: [.creationDateKey]),
                               let creationDate = resourceValues.creationDate {
                                
                                // 获取原始图片的实际尺寸
                                let originalSize = image.size
                                
                                // 创建带有水印的图片
                                let finalImage = NSImage(size: originalSize)
                                finalImage.lockFocus()
                                
                                // 绘制原始图片
                                image.draw(in: NSRect(origin: .zero, size: originalSize))
                                
                                // 绘制水印
                                let dateString = currentDateFormatter.string(from: creationDate)
                                
                                let attributes: [NSAttributedString.Key: Any] = [
                                    .font: fixedFont,
                                    .foregroundColor: currentColor
                                ]
                                
                                let attributedString = NSAttributedString(string: dateString, attributes: attributes)
                                let stringSize = attributedString.size()
                                
                                // 计算自适应边距
                                let adaptiveMargin = calculateAdaptiveMargin(for: imageSize)
                                
                                // 绘制文字，使用等比例边距
                                attributedString.draw(at: NSPoint(
                                    x: originalSize.width - stringSize.width - adaptiveMargin,
                                    y: adaptiveMargin
                                ))
                                
                                finalImage.unlockFocus()
                                
                                // 保存图片
                                let fileName = imageURL.lastPathComponent
                                let savePath = saveURL.appendingPathComponent(fileName)
                                
                                // 根据原始图片格式决定保存格式
                                let imageFormat: NSBitmapImageRep.FileType = imageURL.pathExtension.lowercased() == "heic" ? .jpeg : .png
                                
                                if let tiffData = finalImage.tiffRepresentation,
                                   let bitmapImage = NSBitmapImageRep(data: tiffData) {
                                    // 设置正确的像素密度
                                    bitmapImage.size = originalSize
                                    
                                    // 获取原始图片的像素尺寸
                                    if let originalImage = NSImage(contentsOf: imageURL),
                                       let originalRep = originalImage.representations.first {
                                        // 直接使用原始图片的像素尺寸
                                        let pixelsWide = originalRep.pixelsWide
                                        let pixelsHigh = originalRep.pixelsHigh
                                        
                                        // 创建新的位图表示，使用原始像素尺寸
                                        if let newBitmapImage = NSBitmapImageRep(
                                            bitmapDataPlanes: nil,
                                            pixelsWide: pixelsWide,
                                            pixelsHigh: pixelsHigh,
                                            bitsPerSample: 8,
                                            samplesPerPixel: 4,
                                            hasAlpha: true,
                                            isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0,
                                            bitsPerPixel: 0
                                        ) {
                                            // 将原始图片绘制到新的位图表示上
                                            NSGraphicsContext.saveGraphicsState()
                                            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: newBitmapImage)
                                            finalImage.draw(in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
                                            NSGraphicsContext.restoreGraphicsState()
                                            
                                            // 保存新创建的位图表示
                                            if let imageData = newBitmapImage.representation(using: imageFormat, properties: [:]) {
                                                do {
                                                    try imageData.write(to: savePath)
                                                    successCount += 1
                                                } catch {
                                                    print("保存图片失败：\(error.localizedDescription)")
                                                    failedCount += 1
                                                }
                                            } else {
                                                failedCount += 1
                                            }
                                        } else {
                                            failedCount += 1
                                        }
                                    } else {
                                        // 如果无法获取原始像素尺寸，使用默认方法
                                        if let imageData = bitmapImage.representation(using: imageFormat, properties: [:]) {
                                            do {
                                                try imageData.write(to: savePath)
                                                successCount += 1
                                            } catch {
                                                print("保存图片失败：\(error.localizedDescription)")
                                                failedCount += 1
                                            }
                                        } else {
                                            failedCount += 1
                                        }
                                    }
                                } else {
                                    failedCount += 1
                                }
                            } else {
                                failedCount += 1
                            }
                        } else {
                            failedCount += 1
                        }
                        
                        // 在主线程更新进度
                        DispatchQueue.main.async {
                            processedCount += 1
                        }
                    }
                    
                    // 在主线程更新 UI
                    DispatchQueue.main.async {
                        alertMessage = "处理完成：成功保存 \(successCount) 张照片"
                        if failedCount > 0 {
                            alertMessage += "，\(failedCount) 张照片处理失败"
                        }
                        showAlert = true
                        isProcessing = false
                        selectedImages.removeAll()
                        processedCount = 0
                    }
                }
            }
        } else {
            isProcessing = false
        }
    }
    
    private func calculateAdaptiveFontSize(for imageSize: CGSize) -> CGFloat {
        // 使用图片对角线长度作为参考
        let diagonalLength = sqrt(pow(imageSize.width, 2) + pow(imageSize.height, 2))
        // 字体大小设置为对角线长度的 2%
        let adaptiveFontSize = diagonalLength * 0.02
        
        // 设置最小和最大字体大小限制
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
                        let adaptiveFontSize = calculateAdaptiveFontSize(for: imageSize)
                        let adaptiveMargin = calculateAdaptiveMargin(for: imageSize)
                        
                        // 设置字体和颜色
                        let fixedFont = NSFontManager.shared.convert(defaultFont, toSize: adaptiveFontSize)
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
            Text("选择字体")
                .font(.headline)
            
            // 显示当前选择的字体名称
            Text(selectedFont.displayName ?? "未选择字体")
                .font(.system(size: 16))
            
            // 预览区域
            Text("预览文字 ABC abc 123")
                .font(Font(selectedFont))
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
            
            // 字体选择按钮
            Button("打开字体选择器") {
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
            ColorPicker("选择颜色", selection: Binding(
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
    }
}

#Preview {
    ContentView()
}

