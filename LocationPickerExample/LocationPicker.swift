//
//  LocationPicker.swift
//  LocationPickerExample
//
//  Created by cano on 2025/06/20.
//

/*
 [1] View表示（onAppear）
 ↓
 manager.requestUserLocation()
 ↓
 CLLocationManagerの状態に応じて分岐
 ├── [a] .notDetermined
 │       → ローディング表示（ProgressView）
 │
 ├── [b] .denied
 │       → NoPermissionView を表示
 │       → 設定画面への遷移や再取得要求が可能
 │
 └── [c] .authorized
 → 地図画面表示（MapView + MapSearchBar）
 └── 検索バーにより検索モード切替
 
 ┌────────────┐
 │ 検索文字入力 │
 └────────────┘
 ↓
 manager.searchForPlaces()  ← async MKLocalSearch
 ↓
 検索結果（Placemark[]）表示
 ↓
 ユーザーが候補をタップ
 ↓
 地図の中心・選択状態を updateMapPosition で更新
 showSearchResults = false
 
 ↓
 [2] 地図中心に「ピン」表示
 ↓
 [3] ユーザーが「Select Location」ボタンを押す
 ↓
 coordinates(selectedCoordinates) クロージャ呼び出し
 ↓
 isPresented = false にして Picker を閉じる
 */

import SwiftUI
import CoreLocation
import SimpleToast
@preconcurrency import MapKit

// MARK: - View拡張: locationPickerモディファイアを提供
// 任意のViewに対して全画面カバービューでLocationPickerViewを表示できるようにする
extension View {
    /// 位置情報を選択するためのモディファイア
    /// - Parameters:
    ///   - isPresented: ピッカーの表示状態を制御するバインディング
    ///   - coordinates: ユーザーが選択した位置座標を返すクロージャ（nilの場合は未選択）
    /// - Returns: ピッカーを表示可能なView
    func locationPicker(
        isPresented: Binding<Bool>,
        coordinates: @escaping (CLLocationCoordinate2D?) -> ()
    ) -> some View {
        self
            .fullScreenCover(isPresented: isPresented) {
                LocationPickerView(isPresented: isPresented, coordinates: coordinates)
            }
    }
}

// MARK: - LocationPickerViewの定義
fileprivate struct LocationPickerView: View {
    @Binding var isPresented: Bool
    /// 選択された座標を呼び出し元へ返すクロージャ
    var coordinates: (CLLocationCoordinate2D?) -> ()
    
    // MARK: - View状態管理用プロパティ
    
    /// ユーザー位置・検索・マップ表示状態などを統括管理するロジック
    @StateObject private var manager: LocationManager = .init()
    
    /// 最終的に選択された座標を一時保持するローカル状態（「Select Location」ボタン押下時に使用）
    @State private var selectedCoordinates: CLLocationCoordinate2D?
    
    /// 複数のMap関連ビュー間で共通のMap描画スコープを共有するためのNamespace
    @Namespace private var mapSpace
    
    /// テキストフィールドのフォーカス状態を管理する（検索入力中か否かの判定用）
    @FocusState private var isKeyboardActive: Bool
    
    /// 外部URL（アプリ設定画面）を開くための環境変数
    @Environment(\.openURL) private var openURL
    
    /// 現在表示中のLook Aroundシーン（ピンの位置に基づく）
    @State private var lookAroundScene: MKLookAroundScene? = nil
    @State private var isLocationSelected: Bool = false
    
    @State private var image: UIImage?
    @State private var isShowingPreview = false
    
    @State private var tappedCoordinates: CLLocationCoordinate2D?
    @State private var showToast = false
    
    
    
    var body: some View {
        ZStack {
            // 位置情報の許可状態によって分岐
            if let isPermissionDenied = manager.isPermissionDenied {
                if isPermissionDenied {
                    NoPermissionView()
                } else {
                    ZStack {
                        // 検索結果の一覧ビュー（背面）
                        SearchResultsView()
                        
                        // 地図ビュー（検索結果が非表示時のみ前面）
                        MapView()
                        /*.safeAreaInset(edge: .bottom, spacing: 0) {
                         SelectLocationButton()
                         }*/
                            .opacity(manager.showSearchResults ? 0 : 1)
                            .ignoresSafeArea(.keyboard, edges: .all)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        MapSearchBar()
                    }
                }
            } else {
                // ローディング状態（位置情報の許可取得中）
                Group {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    
                    ProgressView()
                }
            }
        }
        .onAppear(perform: manager.requestUserLocation) // 初回表示時に位置情報取得要求
        .animation(.easeInOut(duration: 0.25), value: manager.showSearchResults)
    }
    
    /// 位置情報未許可時の案内ビュー
    @ViewBuilder
    func NoPermissionView() -> some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            Text("Please allow location permission\nin the app settings!")
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 閉じるボタン
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                    .padding(15)
                    .contentShape(.rect)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            // 「Try Again」と「設定を開く」ボタン
            VStack(spacing: 12) {
                Button("Try Again", action: manager.requestUserLocation)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                
                Button {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                } label: {
                    Text("Go to Settings")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.background)
                        .background(Color.primary, in: .rect(cornerRadius: 12))
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 10)
            }
        }
    }
    
    
    /// 地図ビュー + ピンの中心座標の取得処理 + LookAround表示
    @ViewBuilder
    func MapView() -> some View {
        GeometryReader { geo in
            Map(position: $manager.position, interactionModes: .all){
                UserAnnotation()
                
                if let coord = tappedCoordinates {
                    Annotation("", coordinate: coord) {
                        Image(systemName: "mappin.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.red)
                            .onTapGesture {
                                // タップされた時の処理
                                print("ピンがタップされました")
                                isLocationSelected = true
                                //getLookAroundScene(coordinate: coord)
                            }
                    }
                }
            }
            .mapControls {
                // デフォルトの地図コントロール（ユーザー位置ボタン・方位磁針・ピッチ切替）
                MapUserLocationButton(scope: mapSpace)
                MapCompass(scope: mapSpace)
                MapPitchToggle(scope: mapSpace)
            }
            //.gesture(
            .simultaneousGesture(
                DragGesture(minimumDistance: 0) // タップ相当として使用（位置情報が取れる）
                    .onEnded { value in
                        
                        image = nil
                        // value は DragGesture.Value 型で、タップ/ドラッグ時の情報を含む
                        // ここでは value.location がタップされた位置（Mapビュー内のCGPoint）を表す
                        
                        // 画面サイズ
                        // Mapのサイズを取得
                        let mapSize = geo.size
                        
                        // 画面の中心座標（CGPoint）
                        let center = CGPoint(x: mapSize.width / 2, y: mapSize.height / 2)
                        
                        // タップ位置（value.location）と中心点との水平方向の差を画面幅に対する割合で計算
                        let dx = (value.location.x - center.x) / center.x
                        
                        // タップ位置と中心点との垂直方向の差を画面高さに対する割合で計算
                        let dy = (value.location.y - center.y) / center.y
                        
                        // 現在の地図の表示領域（緯度経度範囲）が取得できている場合
                        if let region = manager.currentRegion {
                            let span = region.span
                            
                            // 中心の緯度から Y方向の比率を使って新しい緯度を算出
                            let newLat = region.center.latitude - dy * span.latitudeDelta / 2
                            
                            // 中心の経度から X方向の比率を使って新しい経度を算出
                            let newLon = region.center.longitude + dx * span.longitudeDelta / 2
                            
                            // 緯度経度を CLLocationCoordinate2D に変換
                            let coord = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
                            
                            // ピン表示および選択結果として反映
                            tappedCoordinates = coord
                            
                            getLookAroundScene(coordinate: coord)
                            // デバッグログ出力
                            print("Tapped: \(coord.latitude), \(coord.longitude)")
                        }
                    }
            )
            .coordinateSpace(name: "MapCoordinateSpace")
            .mapScope(mapSpace)
            .onMapCameraChange { ctx in
                // カメラ移動に応じて現在の中心座標を更新
                manager.currentRegion = ctx.region
                selectedCoordinates = ctx.region.center
            }
            .onAppear {
                print("manager.position: \(manager.position)")
            }
            .overlay(alignment: .bottom) {
                if let image = image {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: 160, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 4)
                            .onTapGesture {
                                isShowingPreview = true
                            }
                        Spacer()
                    }
                    .padding([.leading, .bottom], 20)
                }
            }
            .sheet(isPresented: $isShowingPreview) {
                if let scene = lookAroundScene {
                    LookAroundPreview(initialScene: scene)
                        .ignoresSafeArea()
                        .presentationDetents([.height(320), .fraction(0.6), .large])
                } else {
                    Text("Look Around プレビューは利用できません。")
                        .padding()
                }
            }
            // MKLookAroundViewがあればシートで表示
            /*.sheet(isPresented: $isLocationSelected){
             LookAroundPreview(initialScene: lookAroundScene)
             .ignoresSafeArea()
             .presentationDetents([
             .height(320),
             .fraction(0.6)])
             }*/
        }
    }
    
    // FullScreenCover で表示する専用のView
    struct FullScreenLookAroundView: View {
        // プレビューを閉じるための環境変数
        @Environment(\.dismiss) var dismiss // iOS 15+
        // または @Environment(\.presentationMode) var presentationMode // iOS 13-14
        
        let lookAroundScene: MKLookAroundScene?
        
        var body: some View {
            ZStack(alignment: .topTrailing) { // 右上に閉じるボタンを配置
                if let scene = lookAroundScene {
                    LookAroundPreview(initialScene: scene)
                        .ignoresSafeArea() // セーフエリアを無視して全画面表示
                } else {
                    VStack {
                        Spacer()
                        Text("Look Around プレビューは利用できません。")
                            .font(.headline)
                            .padding()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.8)) // 背景を暗くする
                    .foregroundColor(.white)
                }
                
                // 閉じるボタン
                Button {
                    dismiss() // iOS 15+
                    // または presentationMode.wrappedValue.dismiss() // iOS 13-14
                } label: {
                    Image(systemName: "xmark.circle.fill") // バツマークのアイコン
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding(20) // 右上からの余白
                }
            }
        }
    }
    
    /// 指定座標からLook Aroundプレビューを取得
    func getLookAroundScene(coordinate: CLLocationCoordinate2D) {
        Task.detached {
            let request = MKLookAroundSceneRequest(coordinate: coordinate)
            do {
                let scene = try await request.scene
                DispatchQueue.main.async {
                    lookAroundScene = scene
                    if lookAroundScene != nil {
                        isLocationSelected = true
                        getLookAroundThumbnailWithCompletionHandler(for: coordinate) { resultImage, error in
                            if let image = resultImage {
                                self.image = image
                            } else if let error = error {
                                print(error.localizedDescription)
                            }
                        }
                    }
                }
            } catch {
                print("Error: \(error)")
            }
        }
    }
    
    func getLookAroundThumbnailWithCompletionHandler(
        for coordinate: CLLocationCoordinate2D,
        completion: @escaping (UIImage?, Error?) -> Void
    ) {
        let sceneRequest = MKLookAroundSceneRequest(coordinate: coordinate)
        
        Task { // MKLookAroundSceneRequest.scene は async/await スタイルなのでTask内で実行
            do {
                guard let scene = try await sceneRequest.scene else {
                    let error = NSError(domain: "LookAroundThumbnailError", code: 1, userInfo: [NSLocalizedDescriptionKey: "指定された座標にLook Aroundシーンが見つかりませんでした。"])
                    DispatchQueue.main.async { // メインスレッドでコンプリーションハンドラを呼び出す
                        completion(nil, error)
                    }
                    return
                }
                
                let options = MKLookAroundSnapshotter.Options()
                // options.size = CGSize(width: 400, height: 300) // 必要に応じてサイズを指定
                
                let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
                
                // ここから修正された部分です
                // snapshot と error は既にオプショナル型として渡されるので、
                // 直接 if let でアンラップします。
                snapshotter.getSnapshotWithCompletionHandler { optionalSnapshot, optionalError in
                    // このクロージャは自動的にメインスレッドで実行されます（MapKitの慣例）
                    
                    if let error = optionalError {
                        // エラーがある場合
                        print("Look Aroundサムネイルの取得に失敗しました: \(error.localizedDescription)")
                        completion(nil, error)
                        return
                    }
                    
                    guard let snapshot = optionalSnapshot else {
                        // スナップショット自体がnilの場合
                        let error = NSError(domain: "LookAroundThumbnailError", code: 2, userInfo: [NSLocalizedDescriptionKey: "スナップショットの結果がnilでした。"])
                        print("エラー: \(error.localizedDescription)")
                        completion(nil, error)
                        return
                    }
                    
                    let image = snapshot.image
                    
                    // 成功した画像を返す
                    completion(image, nil)
                }
                
            } catch {
                // シーンリクエストでのエラーをキャッチ
                print("Look Aroundシーンのリクエストに失敗しました: \(error.localizedDescription)")
                DispatchQueue.main.async { // メインスレッドでコンプリーションハンドラを呼び出す
                    completion(nil, error)
                }
            }
        }
    }
    
    /// マップ上部に表示される検索バー UI
    /// - 位置検索の入力、検索状態の管理、戻る操作などを提供
    @ViewBuilder
    func MapSearchBar() -> some View {
        VStack(spacing: 15) {
            // タイトルラベルと左側の戻る／検索解除ボタンを重ねる
            Text("Select Location")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    // 検索結果表示中はキャンセル、それ以外はビューを閉じる
                    Button {
                        if manager.showSearchResults {
                            // キーボードを閉じ、検索結果をクリア
                            isKeyboardActive = false
                            manager.clearSearch()
                            manager.showSearchResults = false
                        } else {
                            // Picker全体を閉じる
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.primary)
                            .contentShape(.rect) // 押しやすくする
                    }
                }
            
            // 検索入力フィールド + アイコン + 削除ボタン
            HStack(spacing: 12) {
                // 虫眼鏡アイコン
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.gray)
                
                // 検索テキストフィールド
                TextField("Search", text: $manager.searchText)
                    .padding(.vertical, 10)
                    .focused($isKeyboardActive) // フォーカス制御
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit {
                        // エンターキーで検索 or クリア
                        if manager.searchText.isEmpty {
                            manager.clearSearch()
                        } else {
                            manager.searchForPlaces()
                        }
                    }
                    .onChange(of: isKeyboardActive) { _, newValue in
                        // フォーカスが当たれば検索候補を表示
                        if newValue {
                            manager.showSearchResults = true
                        }
                    }
                
                // 検索中以外に表示されるクリアボタン
                if manager.showSearchResults && !manager.searchText.isEmpty {
                    Button {
                        manager.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.gray)
                    }
                    .opacity(manager.isSearching ? 0 : 1) // 検索中は非表示
                    .overlay {
                        // 検索中はインジケーター表示
                        ProgressView()
                            .opacity(manager.isSearching ? 1 : 0)
                    }
                }
            }
            .padding(.horizontal, 15)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 10)) // 背景デザイン
        }
        .padding(15)
        .background(.background) // 全体背景
    }
    
    /// 「Select Location」ボタン（マップ下部に表示）
    /// - 地図上の現在の選択位置（ピンの位置）を確定して呼び出し元に渡す
    @ViewBuilder
    func SelectLocationButton() -> some View {
        Button {
            // ビューを閉じる
            isPresented = false
            // 現在選択中の座標をクロージャ経由で返す（nilの場合は選択なし）
            coordinates(selectedCoordinates)
        } label: {
            // ボタンラベル
            Text("Select Location")
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            // 半透明背景 + 丸角装飾
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
        }
        // ボタンの上下左右にパディングを追加（地図との余白）
        .padding(15)
        .background(.background) // 背景色を合わせる（特にLight/Dark対応）
    }
    
    /// 検索結果の一覧表示ビュー
    /// - manager.searchResults にある検索結果（MKPlacemark）を縦に並べて表示
    @ViewBuilder
    func SearchResultsView() -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 15) {
                // 各検索結果を表示用カードビューとして表示
                ForEach(manager.searchResults, id: \.self) { placemark in
                    SearchResultCardView(placemark)
                        .onAppear {
                            // デバッグ用ログ出力（各候補の情報）
                            print(placemark)
                        }
                }
            }
            .padding(15) // 結果リスト全体の内側余白
        }
        .frame(maxWidth: .infinity) // 横幅いっぱいに広げる
        .background(.background)    // システム背景色に合わせる
    }
    
    /// 検索候補 1件ごとの表示ビュー
    /// - 検索結果の名称と住所を表示し、タップで地図に反映
    @ViewBuilder
    func SearchResultCardView(_ placemark: MKPlacemark) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // 名称・住所の表示
                VStack(alignment: .leading, spacing: 8) {
                    Text(placemark.name ?? "") // 施設名等
                    Text(placemark.title ?? placemark.subtitle ?? "") // 詳細な住所情報
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                
                Spacer(minLength: 0) // 右側にスペースを押し出す
                
                // 選択中の場合のみチェックマークを表示
                Image(systemName: "checkmark")
                    .font(.callout)
                    .foregroundStyle(.gray)
                    .opacity(manager.selectedResult == placemark ? 1 : 0)
            }
            
            Divider() // 下線（区切り）
        }
        .contentShape(.rect) // タップ範囲をView全体に拡張
        .onTapGesture {
            isKeyboardActive = false // キーボードを閉じる
            manager.updateMapPosition(placemark) // 地図位置を更新
        }
    }
    
}
// MARK: - CLLocationManager をラップした ObservableObject
// 位置情報の取得・検索・状態管理を担う ViewModel 的なクラス
fileprivate class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    // MARK: - 公開プロパティ（UIと連携）
    
    /// 位置情報の許可が拒否されたか（nil: 未判定 / true: 拒否 / false: 許可）
    @Published var isPermissionDenied: Bool?
    
    /// 現在のマップ表示領域（中心位置と範囲）
    @Published var currentRegion: MKCoordinateRegion?
    
    /// カメラの位置（初期は自動）
    @Published var position: MapCameraPosition = .automatic
    
    /// 取得した現在位置（座標のみ）
    @Published var userCoordinates: CLLocationCoordinate2D?
    
    /// 検索バーの入力文字列
    @Published var searchText: String = ""
    
    /// 検索結果（MKPlacemarkの配列）
    @Published var searchResults: [MKPlacemark] = []
    
    /// 現在選択されている検索候補（タップされたもの）
    @Published var selectedResult: MKPlacemark?
    
    /// 検索結果リストを表示するかどうか
    @Published var showSearchResults: Bool = false
    
    /// 検索処理中かどうか（インジケータ制御用）
    @Published var isSearching: Bool = false
    
    // MARK: - 内部プロパティ
    
    /// CoreLocation のロケーションマネージャ
    private var manager: CLLocationManager = .init()
    
    // MARK: - 初期化
    
    override init() {
        super.init()
        manager.delegate = self
    }
    
    // MARK: - CLLocationManagerDelegate
    
    /// 位置情報の許可ステータスが変更されたときの処理
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        
        // 拒否された場合 true を設定（UIに反映される）
        isPermissionDenied = status == .denied
        
        if status != .denied {
            // 許可されていれば位置情報の取得を開始
            manager.startUpdatingLocation()
        }
    }
    
    /// 位置情報が取得されたときの処理
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinates = locations.first?.coordinate else { return }
        
        // 座標とマップ表示範囲を更新
        userCoordinates = coordinates
        let region = MKCoordinateRegion(
            center: coordinates,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        position = .region(region)
        
        // 不要になったら停止（省電力対策）
        manager.stopUpdatingLocation()
    }
    
    /// 位置情報取得に失敗したときの処理
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // TODO: 必要に応じてエラー処理を追加
    }
    
    // MARK: - 位置情報の要求
    
    /// 位置情報の使用許可をリクエスト（iOS 標準のダイアログ表示）
    func requestUserLocation() {
        manager.requestWhenInUseAuthorization()
    }
    
    // MARK: - 検索処理
    
    /// 現在のマップ範囲内で地名・住所を検索
    func searchForPlaces() {
        guard let currentRegion else { return }
        
        Task { @MainActor in
            isSearching = true
            
            let request = MKLocalSearch.Request()
            request.region = currentRegion
            request.naturalLanguageQuery = searchText
            
            // 検索実行
            guard let response = try? await MKLocalSearch(request: request).start() else {
                isSearching = false
                return
            }
            
            // 結果を抽出して表示
            searchResults = response.mapItems.compactMap { $0.placemark }
            isSearching = false
        }
    }
    
    /// 検索内容と結果をクリア
    func clearSearch() {
        searchText = ""
        searchResults = []
        selectedResult = nil
    }
    
    /// 選択された検索結果にマップ位置を移動
    /// - Parameter placemark: タップされた候補の位置情報
    func updateMapPosition(_ placemark: MKPlacemark) {
        let coordinates = placemark.coordinate
        let region = MKCoordinateRegion(
            center: coordinates,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        position = .region(region)
        selectedResult = placemark
        showSearchResults = false
    }
    
    // MARK: - 解放処理
    
    /// オブジェクト破棄時に位置更新を停止
    deinit {
        manager.stopUpdatingLocation()
    }
}
