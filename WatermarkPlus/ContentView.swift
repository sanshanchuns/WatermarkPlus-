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
    @State private var selectedFontSize: CGFloat = 24
    @State private var showFontSizePicker = false
    @State private var showDateFormatPicker = false
    @State private var isCustomDateFormat = false
    @FocusState private var focusedField: Field?
    
    // 定义可聚焦的字段枚举
    enum Field {
        case processButton
        case alertButton
    }
    
    // 预设字体大小
    private let presetFontSizes: [CGFloat] = [16, 20, 24, 28, 32]
    
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
    
    var body: some View {
        VStack(spacing: 20) {
            // 虚线框区域
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
                    Text("拖放照片到这里\n或点击选择照片/文件夹")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .onTapGesture {
                selectFiles()
            }
            .onDrop(of: [.image], isTargeted: $isTargeted) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (data, error) in
                        if let url = data as? URL {
                            DispatchQueue.main.async {
                                if !selectedImages.contains(url) {
                                    selectedImages.append(url)
                                }
                            }
                        }
                    }
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
            
            // 设置区域
            VStack(spacing: 20) {
                // 日期格式选择区域
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("日期格式")
                            .font(.headline)
                        
                        // 预览当前时间格式
                        Text("预览：\(dateFormatter.string(from: Date()))")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    
                    // 预设日期格式按钮
                    HStack(spacing: 15) {
                        ForEach(presetDateFormats, id: \.name) { preset in
                            Button(action: {
                                dateFormat = preset.format
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
                
                // 字体选择区域
                VStack(alignment: .leading, spacing: 10) {
                    Text("水印字体")
                        .font(.headline)
                    
                    HStack(spacing: 15) {
                        // 默认字体按钮
                        Button(action: {
                            if defaultFontLoaded {
                                selectedFont = NSFont(name: "LED Digital 7", size: selectedFontSize) ?? NSFont.systemFont(ofSize: selectedFontSize)
                            } else {
                                selectedFont = NSFont.systemFont(ofSize: selectedFontSize)
                            }
                            isCustomFont = false
                        }) {
                            Text("LED Digital")
                                .font(.system(size: 16))
                                .frame(width: 120, height: 30)
                                .background(!isCustomFont ? Color.accentColor : Color.clear)
                                .foregroundColor(!isCustomFont ? .white : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        // 自定义字体按钮
                        Button(action: {
                            showFontPicker = true
                        }) {
                            HStack {
                                Image(systemName: "textformat")
                                Text(isCustomFont ? selectedFont.displayName ?? "自定义字体" : "选择字体")
                            }
                            .frame(width: 120, height: 30)
                            .background(isCustomFont ? Color.accentColor : Color.clear)
                            .foregroundColor(isCustomFont ? .white : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // 字体大小选择
                    VStack(alignment: .leading, spacing: 10) {
                        Text("水印大小")
                            .font(.headline)
                        
                        // 预设字体大小按钮
                        HStack(spacing: 15) {
                            ForEach(presetFontSizes, id: \.self) { size in
                                Button(action: {
                                    selectedFontSize = size
                                    updateFont()
                                }) {
                                    Text("\(Int(size))")
                                        .frame(width: 40, height: 30)
                                        .background(selectedFontSize == size ? Color.accentColor : Color.clear)
                                        .foregroundColor(selectedFontSize == size ? .white : .primary)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // 自定义字体大小按钮
                            Button(action: {
                                showFontSizePicker = true
                            }) {
                                Image(systemName: "textformat.size")
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .help("自定义水印大小")
                        }
                    }
                }
                
                // 颜色选择区域
                VStack(alignment: .leading, spacing: 10) {
                    Text("水印颜色")
                        .font(.headline)
                    
                    HStack(spacing: 15) {
                        // 预设颜色按钮
                        ForEach(presetColors, id: \.name) { preset in
                            Button(action: {
                                selectedColor = preset.color
                                isCustomColor = false
                            }) {
                                Circle()
                                    .fill(Color(nsColor: preset.color))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColor == preset.color ? 2 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                        }
                        
                        // 自定义颜色按钮和预览
                        HStack(spacing: 8) {
                            Button(action: {
                                tempColor = selectedColor
                                showColorPicker = true
                            }) {
                                Image(systemName: "paintpalette")
                                    .font(.title2)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .help("自定义颜色")
                            
                            if isCustomColor {
                                Circle()
                                    .fill(Color(nsColor: selectedColor))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                    )
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 20)
            
            // 开始处理按钮
            if !selectedImages.isEmpty {
                Button(action: processImages) {
                    Text("开始处理")
                        .frame(width: 200, height: 40)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
                .focused($focusedField, equals: .processButton)
            } else {
                Button(action: {}) {
                    Text("开始处理")
                        .frame(width: 200, height: 40)
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .frame(minWidth: 600, minHeight: 700)
        .onAppear {
            // 注册自定义字体
            loadDefaultFont()
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
        .sheet(isPresented: $showColorPicker) {
            VStack(spacing: 20) {
                ColorPicker("选择水印颜色", selection: Binding(
                    get: { Color(nsColor: tempColor) },
                    set: { tempColor = NSColor($0) }
                ))
                .padding()
                
                HStack(spacing: 20) {
                    Button("取消") {
                        showColorPicker = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("确定") {
                        selectedColor = tempColor
                        isCustomColor = true
                        showColorPicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom)
            }
            .frame(width: 300, height: 150)
        }
        .sheet(isPresented: $showFontPicker) {
            VStack(spacing: 20) {
                List(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                    Button(action: {
                        if let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 24) {
                            selectedFont = font
                            isCustomFont = true
                            showFontPicker = false
                        }
                    }) {
                        Text(family)
                            .font(.custom(family, size: 16))
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 300, height: 300)
                
                Button("取消") {
                    showFontPicker = false
                }
                .buttonStyle(.bordered)
                .padding(.bottom)
            }
        }
        .sheet(isPresented: $showFontSizePicker) {
            VStack(spacing: 20) {
                HStack {
                    Text("字体大小：")
                    Slider(value: $selectedFontSize, in: 12...72, step: 1)
                    Text("\(Int(selectedFontSize))")
                        .frame(width: 40)
                }
                .padding()
                
                HStack(spacing: 20) {
                    Button("取消") {
                        showFontSizePicker = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("确定") {
                        updateFont()
                        showFontSizePicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom)
            }
            .frame(width: 300, height: 150)
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
    }
    
    private func loadDefaultFont() {
        if let fontURL = Bundle.main.url(forResource: "led-digital-7-1", withExtension: "ttf") {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                defaultFontLoaded = true
                selectedFont = NSFont(name: "LED Digital 7", size: 24) ?? NSFont.systemFont(ofSize: 24)
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
        panel.allowedContentTypes = [.image]
        panel.message = "选择照片或包含照片的文件夹"
        panel.prompt = "选择"
        
        if panel.runModal() == .OK {
            // 在主线程中获取 URLs
            let selectedURLs = panel.urls
            let fileManager = FileManager.default
            unsupportedFormats.removeAll()
            
            // 打印当前焦点状态
//            print("选择文件后 - 当前焦点状态：", focusedField as Any)
//            if let window = NSApp.keyWindow {
//                print("当前第一响应者：", window.firstResponder as Any)
//                print("当前焦点视图：", window.firstResponder?.className ?? "nil")
//
//                // 打印视图层级
//                print("视图层级：")
//                if let contentView = window.contentView {
//                    printViewHierarchy(contentView, level: 0)
//                }
//            }
            
            // 在后台线程处理文件选择
            DispatchQueue.global(qos: .userInitiated).async {
                let supportedExtensionsSet = Set(supportedImageExtensions)
                
                for url in selectedURLs {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            // 如果是目录，使用更高效的方式扫描
                            if let enumerator = fileManager.enumerator(
                                at: url,
                                includingPropertiesForKeys: [.isRegularFileKey],
                                options: [.skipsHiddenFiles],
                                errorHandler: nil
                            ) {
                                // 批量处理文件
                                var batch: [URL] = []
                                for case let fileURL as URL in enumerator {
                                    let pathExtension = fileURL.pathExtension.lowercased()
                                    if !pathExtension.isEmpty {
                                        if supportedExtensionsSet.contains(pathExtension) {
                                            batch.append(fileURL)
                                        } else if !unsupportedFormats.contains(pathExtension) {
                                            DispatchQueue.main.async {
                                                if !unsupportedFormats.contains(pathExtension) {
                                                    unsupportedFormats.append(pathExtension)
                                                }
                                            }
                                        }
                                    }
                                    
                                    // 每100个文件更新一次UI
                                    if batch.count >= 100 {
                                        DispatchQueue.main.async {
                                            selectedImages.append(contentsOf: batch)
                                        }
                                        batch.removeAll()
                                    }
                                }
                                
                                // 处理剩余的文件
                                if !batch.isEmpty {
                                    DispatchQueue.main.async {
                                        selectedImages.append(contentsOf: batch)
                                    }
                                }
                            }
                        } else {
                            // 如果是单个文件，直接检查
                            let pathExtension = url.pathExtension.lowercased()
                            if !pathExtension.isEmpty {
                                if supportedExtensionsSet.contains(pathExtension) {
                                    DispatchQueue.main.async {
                                        selectedImages.append(url)
                                    }
                                } else if !unsupportedFormats.contains(pathExtension) {
                                    DispatchQueue.main.async {
                                        if !unsupportedFormats.contains(pathExtension) {
                                            unsupportedFormats.append(pathExtension)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // 所有文件处理完成后，在主线程中更新UI
                DispatchQueue.main.async {
                    // 移除自动设置焦点的代码
                }
            }
        }
    }
    
    // 辅助函数：打印视图层级
//    private func printViewHierarchy(_ view: NSView, level: Int) {
//        let indent = String(repeating: "  ", count: level)
//        print("\(indent)\(view.className)")
//        if let button = view as? NSButton {
//            print("\(indent)  - 按钮标题：\(button.title)")
//        }
//        for subview in view.subviews {
//            printViewHierarchy(subview, level: level + 1)
//        }
//    }
    
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
                    let currentFont = selectedFont
                    let currentColor = selectedColor
                    let currentDateFormatter = dateFormatter
                    
                    for imageURL in imagesToProcess {
                        if let image = NSImage(contentsOf: imageURL) {
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
                                
                                // 根据图片格式调整字体大小
                                let pathExtension = imageURL.pathExtension.lowercased()
                                let isHeicFormat = pathExtension == "heic"
                                
                                // HEIC 格式使用当前字体大小的 3 倍
                                let adjustedFontSize = isHeicFormat ? selectedFontSize * 3 : selectedFontSize
                                let fixedFont = NSFontManager.shared.convert(currentFont, toSize: adjustedFontSize)
                                
                                let attributes: [NSAttributedString.Key: Any] = [
                                    .font: fixedFont,
                                    .foregroundColor: currentColor
                                ]
                                
                                let attributedString = NSAttributedString(string: dateString, attributes: attributes)
                                let stringSize = attributedString.size()
                                
                                // 计算水印位置，考虑字体大小变化
                                let margin: CGFloat = 20
                                let scaledMargin = isHeicFormat ? margin * 3 : margin
                                
                                // 绘制文字，使用固定边距
                                attributedString.draw(at: NSPoint(
                                    x: originalSize.width - stringSize.width - scaledMargin,
                                    y: scaledMargin
                                ))
                                
                                finalImage.unlockFocus()
                                
                                // 保存图片
                                let fileName = imageURL.lastPathComponent
                                let savePath = saveURL.appendingPathComponent(fileName)
                                
                                // 根据原始图片格式决定保存格式
                                let imageFormat: NSBitmapImageRep.FileType = pathExtension == "heic" ? .jpeg : .png
                                
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
                        
                        // 移除自动设置焦点的代码
                    }
                }
            }
        } else {
            isProcessing = false
        }
    }
    
    private func updateFont() {
        if isCustomFont {
            selectedFont = NSFontManager.shared.convert(selectedFont, toSize: selectedFontSize)
        } else if defaultFontLoaded {
            selectedFont = NSFont(name: "LED Digital 7", size: selectedFontSize) ?? NSFont.systemFont(ofSize: selectedFontSize)
        } else {
            selectedFont = NSFont.systemFont(ofSize: selectedFontSize)
        }
    }
}

#Preview {
    ContentView()
}

