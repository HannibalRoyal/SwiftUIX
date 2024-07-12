//
// Copyright (c) Vatsal Manot
//

@_spi(Internal) import _SwiftUIX
import Swift
import SwiftUI

#if os(iOS) || os(macOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)

@available(macCatalystApplicationExtension, unavailable)
@available(iOSApplicationExtension, unavailable)
@available(tvOSApplicationExtension, unavailable)
public struct _AppKitOrUIKitHostingWindowContent<Content: View>: View {
    @PersistentObject private var _windowBox: _SwiftUIX_ObservableWeakReferenceBox<AppKitOrUIKitHostingWindow<Content>>
    @PersistentObject private var _popoverBox: _SwiftUIX_ObservableWeakReferenceBox<_AnyAppKitOrUIKitHostingPopover>
    
    var isEmptyView: Bool {
        Content.self == EmptyView.self
    }
    
    var _window: AppKitOrUIKitHostingWindow<Content>? {
        get {
            _windowBox.wrappedValue
        } nonmutating set {
            _windowBox.wrappedValue = newValue
            
            if let popover = self._popover {
                DispatchQueue.main.async {
                    if popover.isDetached {
                        assert(_window != nil)
                        
                        self._popover = nil
                        self.wasInitializedWithPopover = false
                    }
                }
            }
        }
    }
    
    var _popover: _AnyAppKitOrUIKitHostingPopover? {
        get{
            _popoverBox.wrappedValue
        } nonmutating set {
            _popoverBox.wrappedValue = newValue
        }
    }
    
    var content: Content
    var isPresented: Bool
    
    @State private var wasInitializedWithPopover: Bool
    @State private var popoverWindowDidAppear: Bool = false
    @State private var queuedWindowUpdates: [(AppKitOrUIKitHostingWindow<Content>) -> Void] = []
    
    private var presentationManager: _PresentationManager {
        _PresentationManager(
            _window: _windowBox,
            _popover: _popoverBox
        )
    }
    
    var initialized: Bool = true
    
    init(
        window: AppKitOrUIKitHostingWindow<Content>?,
        popover: _AnyAppKitOrUIKitHostingPopover?,
        content: Content,
        isPresented: Bool = false
    ) {
        weak var _window = window
        weak var _popover = popover
        
        if window == nil && popover == nil {
            initialized = false
        }
        
        self.__windowBox = .init(wrappedValue: .init(_window))
        self.__popoverBox = .init(wrappedValue: .init(_popover))
        self.content = content
        self.isPresented = isPresented
        self._wasInitializedWithPopover = .init(initialValue: _popover != nil)
    }
    
    public var body: some View {
        if initialized {
            _UnaryViewAdaptor(_actualWindowContent)
                .environment(\._windowProxy, WindowProxy(window: _window))
                .environment(\.presentationManager, presentationManager)
                .modifier(
                    _AppKitOrUIKitHostingWindowUpdateQueueing(
                        queueWindowUpdate: self._queueWindowUpdate
                    )
                )
                ._onChange(of: _window != nil) { _ in
                    DispatchQueue.main.async {
                        _flushWindowUpdates()
                    }
                }
                ._onChange(of: queuedWindowUpdates.count) { _ in
                    DispatchQueue.main.async {
                        _flushWindowUpdates()
                    }
                }
                .onChangeOfFrame { [_popoverBox] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                        _window?.applyPreferredConfiguration()
                    }
                    
                    // FIXME? Migrated from popover content wrapper.
                    if !popoverWindowDidAppear {
                        _popoverBox.wrappedValue?._SwiftUIX_layoutImmediately()
                    }
                }
                .onPreferenceChange(_AppKitOrUIKitHostingPopoverPreferences._PreferenceKey.self) { [_popoverBox] popoverPreferences in
                    _popoverBox.wrappedValue?._SwiftUIX_hostingPopoverPreferences = popoverPreferences
                }
        } else {
            ZeroSizeView()
        }
    }
    
    @ViewBuilder
    private var _actualWindowContent: some View {
        if wasInitializedWithPopover {
            content.onAppear {
                popoverWindowDidAppear = true
            }
        } else {
            LazyAppearView {
                if _window != nil {
                    content
                }
            }
            .animation(.none)
        }
    }
    
    private func _queueWindowUpdate(
        _ update: @escaping (AppKitOrUIKitHostingWindow<Content>) -> Void
    ) {
        if let window = _window {
            update(window)
            
            _flushWindowUpdates()
        } else {
            queuedWindowUpdates.append(update)
        }
    }
    
    private func _flushWindowUpdates() {
        guard let _window = _window, !queuedWindowUpdates.isEmpty else {
            return
        }
        
        queuedWindowUpdates.forEach({ $0(_window) })
        queuedWindowUpdates = []
        
        _didFlushWindowUpdates()
    }
    
    private func _didFlushWindowUpdates() {
        guard let _window = _window else {
            return
        }

        if let _popover {
            _popover._SwiftUIX_hostingPopoverPreferences = _window._SwiftUIX_hostingPopoverPreferences
        }
    }
}

// MARK: - Internal

extension _AppKitOrUIKitHostingWindowContent {
    struct _PresentationManager: PresentationManager {
        @_SwiftUIX_ObservableWeakReferenceBox
        var _window: AppKitOrUIKitHostingWindow<Content>?
        @_SwiftUIX_ObservableWeakReferenceBox
        var _popover: _AnyAppKitOrUIKitHostingPopover?
        
        var isPresented: Bool {
            if let _popover {
                return _popover.isShown
            } else if let _window {
                return _window.isHidden == false
            } else {
                return false
            }
        }
        
        func dismiss() {
            _popover?._SwiftUIX_dismiss()
            _window?._SwiftUIX_dismiss()
        }
    }
}

fileprivate struct _AppKitOrUIKitHostingWindowUpdateQueueing<WindowContent: View>: ViewModifier {
    let queueWindowUpdate: (@escaping (AppKitOrUIKitHostingWindow<WindowContent>) -> Void) -> Void
    
    func body(content: Content) -> some View {
        content
            .onPreferenceChange(_SwiftUIX_WindowPreferenceKeys.BackgroundColor.self) { backgroundColor in
                queueWindowUpdate {
                    $0._SwiftUIX_windowConfiguration.backgroundColor = backgroundColor
                }
            }
            .onPreferenceChange(_SwiftUIX_WindowPreferenceKeys.AllowsTouchesToPassThrough.self) { allowTouchesToPassThrough in
                queueWindowUpdate {
                    $0._SwiftUIX_windowConfiguration.allowTouchesToPassThrough = allowTouchesToPassThrough ?? false
                }
            }
            .onPreferenceChange(_SwiftUIX_WindowPreferenceKeys.Position.self) { windowPosition in
                guard let windowPosition else {
                    return
                }
                
                queueWindowUpdate {
                    $0._SwiftUIX_windowConfiguration.windowPosition = windowPosition
                }
            }
            .onPreferenceChange(_SwiftUIX_WindowPreferenceKeys.TitleBarIsHidden.self) { isTitleBarHidden in
                queueWindowUpdate {
                    $0._SwiftUIX_windowConfiguration.isTitleBarHidden = isTitleBarHidden
                }
            }
            .onPreferenceChange(_SwiftUIX_WindowPreferenceKeys.BackgroundColor.self) { backgroundColor in
                queueWindowUpdate {
                    $0._SwiftUIX_windowConfiguration.backgroundColor = backgroundColor
                }
            }
            .onPreferenceChange(_AppKitOrUIKitHostingPopoverPreferences._PreferenceKey.self) { popoverPreferences in
                queueWindowUpdate {
                    $0._SwiftUIX_hostingPopoverPreferences = popoverPreferences
                }
            }
    }
}

enum _SwiftUIX_WindowPreferenceKeys {
    final class AllowsTouchesToPassThrough: TakeLastPreferenceKey<Bool> {
        
    }
    
    final class Position: TakeLastPreferenceKey<_CoordinateSpaceRelative<CGPoint>> {
        
    }
    
    final class TitleBarIsHidden: TakeLastPreferenceKey<Bool> {
        
    }
    
    final class BackgroundColor: TakeLastPreferenceKey<Color> {
        
    }
}

#endif
