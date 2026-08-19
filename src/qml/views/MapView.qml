import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 地图视图（在线瓦片地图）：
// - 用 tileProvider 下载天地图/OSM 瓦片，Canvas 拼接渲染
// - 支持缩放/平移/回中/跟随、街道/影像图层切换
// - 展示飞艇位置(带航向)、历史轨迹、Home点、距离与方位（当前为模拟数据占位）
Item {
    id: root
    property QtObject themeRoot: null

    // ===== 地图状态（Web Mercator）=====
    property double zoom: 14
    // 默认定位：杭州余杭 · 良渚文化村（东经120.029 / 北纬30.365）
    property double centerLon: 120.029
    property double centerLat: 30.365
    property int mapLayer: 0            // 0=街道 1=影像
    property bool follow: true          // 跟随飞艇
    property int tileTick: 0            // 瓦片加载后自增，触发重绘

    // ===== 飞艇模拟数据（提升到顶层 main.qml 常驻）=====
    // 轨迹/位置/航向/距离等由顶层每秒更新，本页只读展示。这样切出地图页再切回，
    // 仍能看到完整连续的轨迹（后台持续累积），而非切出期间漏采样的断线。
    readonly property var airPos:  root.themeRoot ? root.themeRoot.mapAirPos : ({lon:120.029, lat:30.365})
    readonly property double heading: root.themeRoot ? root.themeRoot.mapHeading : 0
    readonly property double alt:   root.themeRoot ? root.themeRoot.mapAlt : 150
    readonly property double speed: root.themeRoot ? root.themeRoot.mapSpeed : 12.5
    readonly property var track:   root.themeRoot ? root.themeRoot.mapTrack : []
    readonly property var homePos: root.themeRoot ? root.themeRoot.mapHomePos : ({lon:120.029, lat:30.365})
    readonly property double dist:   root.themeRoot ? root.themeRoot.mapDist : 0
    readonly property double bearing: root.themeRoot ? root.themeRoot.mapBearing : 0
    readonly property int mapTick: root.themeRoot ? root.themeRoot.mapTick : 0

    // 顶层每秒更新飞艇位置 → mapTick 变化 → 重绘地图（展示最新位置与轨迹）
    // 跟随模式下同步顶层中心到本地视口（跟随逻辑在顶层 Timer，本地需联动否则不跟随）
    onMapTickChanged: {
        if (root.follow && root.themeRoot) {
            root.centerLon = root.themeRoot.mapCenterLon
            root.centerLat = root.themeRoot.mapCenterLat
        }
        canvas.requestPaint()
    }

    // 飞控 fc 遥测（左上角悬浮卡）：带 dataTick 依赖，随串口 fc 数据实时刷新
    function fcLon() { void root.themeRoot.dataTick; const v=bridge.value("fc","lon"); return isNaN(v)?"--":v.toFixed(6)+"°" }
    function fcLat() { void root.themeRoot.dataTick; const v=bridge.value("fc","lat"); return isNaN(v)?"--":v.toFixed(6)+"°" }
    function fcAlt() { void root.themeRoot.dataTick; return isNaN(bridge.value("fc","alt"))?"--":bridge.value("fc","alt").toFixed(1)+" m" }
    function fcGs() {
        void root.themeRoot.dataTick
        const vx=bridge.value("fc","vx"), vy=bridge.value("fc","vy")
        if (isNaN(vx)||isNaN(vy)) return "--"
        return Math.sqrt(vx*vx+vy*vy).toFixed(1)+" m/s"
    }
    function fcSigned(key) {
        void root.themeRoot.dataTick
        const v=bridge.value("fc", key)
        if (isNaN(v)) return "--"
        return (v>=0?"+":"")+v.toFixed(1)+" m/s"
    }
    function fcYaw() { void root.themeRoot.dataTick; return isNaN(bridge.value("fc","yaw"))?"--":bridge.value("fc","yaw").toFixed(1)+"°" }
    function fcVz() { return root.fcSigned("vz") }

    // ===== 墨卡托投影 =====
    function worldSize() { return 256 * Math.pow(2, root.zoom) }
    function lonToX(lon) { return (lon + 180) / 360 * root.worldSize() }
    function latToY(lat) {
        const rad = lat * Math.PI / 180
        const y = (1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2
        return y * root.worldSize()
    }
    function xToLon(x) { return x / root.worldSize() * 360 - 180 }
    function yToLat(y) {
        const n = Math.PI - 2 * Math.PI * y / root.worldSize()
        return 180 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)))
    }
    // 世界坐标 → 屏幕坐标（相对左上角）
    function screenX(wx) { return wx - (root.lonToX(root.centerLon) - canvas.width / 2) }
    function screenY(wy) { return wy - (root.latToY(root.centerLat) - canvas.height / 2) }

    // 瓦片本地路径（与 C++ cachePath 一致：含图源维度，切图源不误读旧缓存）
    function tilePath(z, x, y) {
        return tileProvider.cacheRoot() + "/" + tileProvider.mapSource() + "/" + root.mapLayer + "/" + z + "/" + x + "/" + y + ".png"
    }
    // 已发出请求的瓦片集合（避免重复下载）
    property var reqSet: new Object()
    function tileUrl(z, x, y) {
        const key = z + "/" + x + "/" + y + "/" + root.mapLayer
        // 失败重试退避：上次失败时间戳仍在退避窗口内（30s）则跳过，避免
        // 网络不可达/权限错误(403)时 onPaint 每秒全量重试造成请求洪峰
        const t = root.reqSet[key]
        if (t === true) return
        if (typeof t === "number" && Date.now() - t < 30000) return
        root.reqSet[key] = true
        tileProvider.requestTile(z, x, y, root.mapLayer)
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.themeRoot.colCard
        border.color: root.themeRoot.colLine
        clip: true

        // ===== 瓦片 + 飞艇 Canvas =====
        Canvas {
            id: canvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const vw = width, vh = height
                // 圆角裁剪：Rectangle 的 clip 仅按外框矩形裁剪（不含圆角），
                // 故在 Canvas 内用圆角路径 clip，使瓦片/轨迹/标记全部被圆角遮罩
                const r = 14
                ctx.beginPath()
                ctx.moveTo(r, 0)
                ctx.arcTo(vw, 0, vw, vh, r)
                ctx.arcTo(vw, vh, 0, vh, r)
                ctx.arcTo(0, vh, 0, 0, r)
                ctx.arcTo(0, 0, vw, 0, r)
                ctx.closePath()
                ctx.clip()
                const TLx = root.lonToX(root.centerLon) - vw / 2
                const TLy = root.latToY(root.centerLat) - vh / 2
                const z = Math.round(root.zoom)
                // 平铺背景
                ctx.fillStyle = root.themeRoot.colCard2
                ctx.fillRect(0, 0, vw, vh)
                // 铺瓦片
                const t0 = Math.floor(TLx / 256), t1 = Math.ceil((TLx + vw) / 256)
                const tt0 = Math.floor(TLy / 256), tt1 = Math.ceil((TLy + vh) / 256)
                for (let tx = t0; tx <= t1; tx++) {
                    for (let ty = tt0; ty <= tt1; ty++) {
                        const url = "file://" + root.tilePath(z, tx, ty)
                        if (canvas.isImageLoaded(url)) {
                            ctx.drawImage(url, tx * 256 - TLx, ty * 256 - TLy)
                        } else {
                            root.tileUrl(z, tx, ty)
                        }
                    }
                }
                // 轨迹
                if (root.track.length > 1) {
                    ctx.strokeStyle = root.themeRoot.colPrimary
                    ctx.lineWidth = 2.5
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    for (let i = 0; i < root.track.length; i++) {
                        const sx = root.screenX(root.lonToX(root.track[i].lon))
                        const sy = root.screenY(root.latToY(root.track[i].lat))
                        i === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy)
                    }
                    ctx.stroke()
                }
                // Home点
                const hx = root.screenX(root.lonToX(root.homePos.lon))
                const hy = root.screenY(root.latToY(root.homePos.lat))
                ctx.fillStyle = root.themeRoot.colOk
                ctx.beginPath(); ctx.arc(hx, hy, 6, 0, Math.PI * 2); ctx.fill()
                ctx.strokeStyle = "white"; ctx.lineWidth = 2
                ctx.beginPath(); ctx.arc(hx, hy, 9, 0, Math.PI * 2); ctx.stroke()
                // 起飞点文字
                ctx.fillStyle = root.themeRoot.colText2
                ctx.font = "11px sans-serif"
                ctx.fillText("HOME", hx + 12, hy - 4)
                // 飞艇（带航向的三角箭头）
                const ax = root.screenX(root.lonToX(root.airPos.lon))
                const ay = root.screenY(root.latToY(root.airPos.lat))
                ctx.save()
                ctx.translate(ax, ay)
                ctx.rotate(root.heading * Math.PI / 180)
                ctx.fillStyle = root.themeRoot.colErr
                ctx.beginPath()
                ctx.moveTo(12, 0); ctx.lineTo(-9, 8); ctx.lineTo(-9, -8)
                ctx.closePath(); ctx.fill()
                ctx.strokeStyle = "white"; ctx.lineWidth = 1.5; ctx.stroke()
                ctx.restore()
            }
            // 瓦片加载完成 → 重绘
            Connections {
                target: canvas
                function onImageLoaded() { canvas.requestPaint() }
            }
        }

        // 瓦片下载完成信号
        Connections {
            target: tileProvider
            function onTileLoaded(z, x, y, layer, path) {
                if (layer !== root.mapLayer) return
                canvas.loadImage("file://" + path)
                canvas.requestPaint()
            }
            // 下载失败：记录失败时间戳用于退避重试（避免地图持久白块的同时，
            // 也防止网络不可达时每秒全量重试造成请求洪峰）
            function onTileFailed(z, x, y, layer) {
                const key = z + "/" + x + "/" + y + "/" + layer
                root.reqSet[key] = Date.now()
            }
        }

        // 图源变化（切天地图/OSM）→ 清请求缓存并重绘
        Connections {
            target: tileProvider
            function onSourceChanged() {
                root.reqSet = new Object()
                canvas.requestPaint()
            }
        }

        // ===== 顶部悬浮信息卡（保持原样式，仅增补参数）=====
        Rectangle {
            anchors.top: parent.top; anchors.left: parent.left
            anchors.margins: 14
            width: 240
            radius: 12
            color: root.themeRoot.colCard2
            border.color: root.themeRoot.colLine
            Column {
                anchors.fill: parent; anchors.margins: 12; spacing: 5
                Text { text: "● 飞艇遥测"; color: root.themeRoot.colText; font.pixelSize: 12; font.bold: true }
                Repeater {
                    model: [
                        ["高度", root.fcAlt()],
                        ["地速", root.fcGs()],
                        ["东向速度", root.fcSigned("vx")],
                        ["北向速度", root.fcSigned("vy")],
                        ["升降率", root.fcVz()],
                        ["航向", root.fcYaw()],
                        ["经度", root.fcLon()],
                        ["纬度", root.fcLat()]
                    ]
                    Rectangle {
                        width: 216; height: 24; color: "transparent"
                        Row {
                            spacing: 6
                            Text { text: modelData[0]; color: root.themeRoot.colText2; font.pixelSize: 12; width: 66 }
                            Text { text: modelData[1]; color: root.themeRoot.colPrimary; font.pixelSize: 12; font.family: "monospace"; font.weight: Font.DemiBold }
                        }
                    }
                }
            }
        }

        // ===== 右上角操作按钮 =====
        // z 必须高于下方全屏 dragArea（QML 后定义者 z 序更高），否则点击被
        // 拖拽 MouseArea 拦截、按钮全部失效
        Column {
            z: 100
            anchors.top: parent.top; anchors.right: parent.right
            anchors.margins: 14
            spacing: 8
            Row {
                spacing: 6
                Repeater {
                    model: ["街道", "影像"]
                    Button {
                        // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                        scale: pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        HoverHandler {
                            id: hover_1
                            cursorShape: Qt.PointingHandCursor
                        }
                        width: 52; height: 30
                        text: modelData
                        padding: 0
                        background: Rectangle { radius: 8; color: root.mapLayer === index ? root.themeRoot.colPrimarySoft : root.themeRoot.colCard2; border.color: root.mapLayer === index ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                        contentItem: Text {
                            text: parent.text
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: root.mapLayer === index ? root.themeRoot.colPrimary : root.themeRoot.colText2
                            font.pixelSize: 12; font.bold: root.mapLayer === index
                        }
                        onClicked: { root.mapLayer = index; root.reqSet = new Object(); canvas.requestPaint() }
                    }
                }
            }
            Row {
                spacing: 6
                Button {
                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                    scale: pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    HoverHandler {
                        id: hover_2
                        cursorShape: Qt.PointingHandCursor
                    }
                    width: 40; height: 30; text: "＋"
                    padding: 0
                    background: Rectangle {
                        radius: 8; color: root.themeRoot.colCard2; border.color: (hover_2.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.themeRoot.colText; font.pixelSize: 16
                    }
                    onClicked: { root.zoom = Math.min(18, root.zoom + 1); canvas.requestPaint() }
                }
                Button {
                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                    scale: pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    HoverHandler {
                        id: hover_3
                        cursorShape: Qt.PointingHandCursor
                    }
                    width: 40; height: 30; text: "－"
                    padding: 0
                    background: Rectangle {
                        radius: 8; color: root.themeRoot.colCard2; border.color: (hover_3.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.themeRoot.colText; font.pixelSize: 16
                    }
                    onClicked: { root.zoom = Math.max(3, root.zoom - 1); canvas.requestPaint() }
                }
                Button {
                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                    scale: pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    HoverHandler {
                        id: hover_4
                        cursorShape: Qt.PointingHandCursor
                    }
                    width: 40; height: 30; text: "回中"
                    padding: 0
                    background: Rectangle {
                        radius: 8; color: root.themeRoot.colCard2; border.color: (hover_4.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text {
                        text: parent.text
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.themeRoot.colText2; font.pixelSize: 11
                    }
                    onClicked: { root.centerLon = root.homePos.lon; root.centerLat = root.homePos.lat; canvas.requestPaint() }
                }
                Button {
                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                    scale: pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    HoverHandler {
                        id: hover_5
                        cursorShape: Qt.PointingHandCursor
                    }
                    width: 46; height: 30; text: "跟随"
                    padding: 0
                    background: Rectangle { radius: 8; color: root.follow ? root.themeRoot.colPrimarySoft : root.themeRoot.colCard2; border.color: root.follow ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                    contentItem: Text {
                        // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                        scale: dragArea.pressed ? 0.96 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        text: parent.text
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.follow ? root.themeRoot.colPrimary : root.themeRoot.colText2
                        font.pixelSize: 11; font.bold: root.follow
                    }
                    onClicked: root.follow = !root.follow
                }
            }
        }

        // ===== 平移 / 缩放交互 =====
        MouseArea {
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            id: dragArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            property double lastX: 0
            property double lastY: 0
            onPressed: { root.follow = false; lastX = mouse.x; lastY = mouse.y }
            onPositionChanged: {
                if (pressed) {
                    const dx = mouse.x - lastX, dy = mouse.y - lastY
                    lastX = mouse.x; lastY = mouse.y
                    // 世界坐标随拖拽反向移动
                    const newCx = root.lonToX(root.centerLon) - dx
                    const newCy = root.latToY(root.centerLat) - dy
                    root.centerLon = root.xToLon(newCx)
                    root.centerLat = root.yToLat(newCy)
                    canvas.requestPaint()
                }
            }
            onWheel: {
                const factor = wheel.angleDelta.y > 0 ? 1 : -1
                root.zoom = Math.max(3, Math.min(18, root.zoom + factor))
                canvas.requestPaint()
            }
        }
    }

    // ===== 地图视口状态与顶层 main.qml 同步（切页不重置）=====
    // MapView 用 Loader 懒加载，切走即销毁、切回重建。
    // - restoreMapState：本视图被重建加载时，从顶层读回上次切换前保存的状态
    // - onDestruction：切出本页 / 销毁前，把当前视口状态写回顶层保存
    function restoreMapState() {
        if (!root.themeRoot) return
        root.zoom = root.themeRoot.mapZoom
        root.centerLon = root.themeRoot.mapCenterLon
        root.centerLat = root.themeRoot.mapCenterLat
        root.mapLayer = root.themeRoot.mapLayer
        root.follow = root.themeRoot.mapFollow
        // 轨迹/位置由顶层常驻维护（readonly 绑定），进入本页时重绘一次展示当前轨迹
        canvas.requestPaint()
    }
    Component.onDestruction: {
        if (!root.themeRoot) return
        root.themeRoot.mapZoom = root.zoom
        root.themeRoot.mapCenterLon = root.centerLon
        root.themeRoot.mapCenterLat = root.centerLat
        root.themeRoot.mapLayer = root.mapLayer
        root.themeRoot.mapFollow = root.follow
    }
}