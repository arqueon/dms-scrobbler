import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Services

Item {
    id: root

    property bool verticalMode: false
    property real barSpan: 20
    property int barCount: 6
    property bool stretchToWidth: false
    property var cavaService: null
    property string sourceMode: "mediaOnly"
    property bool showWhenIdle: false
    property string visualizerStyle: "bars"
    property string barAlignment: "center"
    property string channelMode: "mono"
    property color solidColor: Theme.primary
    property bool useGradient: false
    property color gradientStartColor: Theme.primary
    property color gradientEndColor: Theme.secondary
    property real responseCurve: 0.5
    property real attackSmoothing: 0.75
    property real releaseSmoothing: 0.35
    property bool peakHoldEnabled: false
    property int peakHoldMs: 450
    readonly property var activeCavaService: root.cavaService || CavaService
    property var activePlayer: MprisController.activePlayer
    readonly property bool hasActiveMedia: activePlayer !== null
    readonly property bool isPlaying: hasActiveMedia && activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property bool shouldBindToAudio: sourceMode === "allAudio" || isPlaying || showWhenIdle
    readonly property int effectiveBarCount: Math.max(1, barCount)
    readonly property real baseBarWidth: 2
    readonly property real baseSpacing: 1.5
    readonly property real computedSpacing: stretchToWidth ? (effectiveBarCount > 1 ? 1 : 0) : baseSpacing
    readonly property real computedBarWidth: {
        if (!stretchToWidth)
            return baseBarWidth;
        const totalSpacing = computedSpacing * Math.max(0, effectiveBarCount - 1);
        return Math.max(1, (barSpan - totalSpacing) / effectiveBarCount);
    }
    readonly property real contentSpan: stretchToWidth ? barSpan : (effectiveBarCount * computedBarWidth + Math.max(0, effectiveBarCount - 1) * computedSpacing)
    readonly property string effectiveVisualizerStyle: visualizerStyle === "centeredBars" ? "bars" : visualizerStyle

    width: verticalMode ? 20 : barSpan
    height: verticalMode ? barSpan : 20

    Loader {
        active: shouldBindToAudio

        sourceComponent: Component {
            Ref {
                service: root.activeCavaService
            }
        }
    }

    readonly property real maxBarHeight: 18
    readonly property real minBarHeight: 3
    readonly property real heightRange: maxBarHeight - minBarHeight
    property var barHeights: []
    property var peakHeights: []
    property var peakTimes: []

    function clampHeight(value) {
        return Math.max(minBarHeight, Math.min(maxBarHeight, value));
    }

    function barColorAt(index) {
        if (!useGradient)
            return solidColor;
        const mix = effectiveBarCount <= 1 ? 0 : index / Math.max(1, effectiveBarCount - 1);
        return Qt.rgba(gradientStartColor.r + (gradientEndColor.r - gradientStartColor.r) * mix, gradientStartColor.g + (gradientEndColor.g - gradientStartColor.g) * mix, gradientStartColor.b + (gradientEndColor.b - gradientStartColor.b) * mix, gradientStartColor.a + (gradientEndColor.a - gradientStartColor.a) * mix);
    }

    function gradientColorAtMix(mix) {
        if (!useGradient)
            return solidColor;
        const clampedMix = Math.max(0, Math.min(1, mix));
        return Qt.rgba(gradientStartColor.r + (gradientEndColor.r - gradientStartColor.r) * clampedMix, gradientStartColor.g + (gradientEndColor.g - gradientStartColor.g) * clampedMix, gradientStartColor.b + (gradientEndColor.b - gradientStartColor.b) * clampedMix, gradientStartColor.a + (gradientEndColor.a - gradientStartColor.a) * clampedMix);
    }

    function normalizedLevelAt(index) {
        const rawLevel = sampledLevel(index);
        const clampedLevel = Math.max(0, Math.min(100, rawLevel));
        const normalizedLevel = clampedLevel / 100.0;
        const curvedLevel = normalizedLevel <= 0 ? 0 : Math.pow(normalizedLevel, Math.max(0.05, responseCurve));
        return Math.max(0, Math.min(1, curvedLevel));
    }

    function alignedY(barHeight) {
        switch (barAlignment) {
        case "top":
            return 0;
        case "bottom":
            return 20 - barHeight;
        default:
            return (20 - barHeight) / 2;
        }
    }

    function alignedX(barWidth) {
        switch (barAlignment) {
        case "top":
            return 0;
        case "bottom":
            return 20 - barWidth;
        default:
            return (20 - barWidth) / 2;
        }
    }

    function waveYAt(index) {
        const normalized = normalizedLevelAt(index);
        const travel = 16;
        switch (barAlignment) {
        case "top":
            return normalized * travel;
        case "bottom":
            return 18 - normalized * travel;
        default:
            return 9 - normalized * 8;
        }
    }

    function dottedBarCount(index) {
        const normalized = normalizedLevelAt(index);
        return Math.max(1, Math.round(1 + normalized * 7));
    }

    function resetBarHeights() {
        const values = [];
        const peaks = [];
        const times = [];
        for (let i = 0; i < effectiveBarCount; i++) {
            values.push(minBarHeight);
            peaks.push(minBarHeight);
            times.push(0);
        }
        barHeights = values;
        peakHeights = peaks;
        peakTimes = times;
    }

    function sampledLevel(index) {
        const values = root.activeCavaService?.values || [];
        const leftValues = values;
        const rightValues = values;
        if (values.length === 0)
            return 0;
        if (values.length === 1)
            return values[0];
        if (effectiveBarCount <= 1)
            return values[0];

        if (channelMode === "split" || channelMode === "splitReverse") {
            const halfCount = Math.max(1, Math.ceil(effectiveBarCount / 2));
            const usingRightChannel = index >= halfCount;
            let halfIndex = usingRightChannel ? (index - halfCount) : index;
            if (channelMode === "splitReverse" && usingRightChannel)
                halfIndex = Math.max(0, halfCount - 1 - halfIndex);
            const sourceValues = usingRightChannel ? rightValues : leftValues;
            const splitPosition = (halfIndex / Math.max(1, halfCount - 1)) * (Math.max(1, sourceValues.length) - 1);
            const splitLowerIndex = Math.floor(splitPosition);
            const splitUpperIndex = Math.min(sourceValues.length - 1, Math.ceil(splitPosition));
            const splitMix = splitPosition - splitLowerIndex;
            const splitLowerValue = sourceValues[splitLowerIndex] ?? 0;
            const splitUpperValue = sourceValues[splitUpperIndex] ?? splitLowerValue;
            return splitLowerValue + (splitUpperValue - splitLowerValue) * splitMix;
        }

        if (channelMode === "centerOut" || channelMode === "outsideIn") {
            const center = (effectiveBarCount - 1) / 2;
            const maxDistance = Math.max(0.5, center);
            const distanceNormalized = Math.abs(index - center) / maxDistance;
            const positionFactor = channelMode === "centerOut" ? distanceNormalized : (1 - distanceNormalized);
            const mirroredPosition = Math.max(0, Math.min(1, positionFactor)) * (values.length - 1);
            const mirroredLowerIndex = Math.floor(mirroredPosition);
            const mirroredUpperIndex = Math.min(values.length - 1, Math.ceil(mirroredPosition));
            const mirroredMix = mirroredPosition - mirroredLowerIndex;
            const mirroredLowerValue = values[mirroredLowerIndex] ?? 0;
            const mirroredUpperValue = values[mirroredUpperIndex] ?? mirroredLowerValue;
            return mirroredLowerValue + (mirroredUpperValue - mirroredLowerValue) * mirroredMix;
        }

        const position = (index / Math.max(1, effectiveBarCount - 1)) * (values.length - 1);
        const lowerIndex = Math.floor(position);
        const upperIndex = Math.min(values.length - 1, Math.ceil(position));
        const mix = position - lowerIndex;
        const lowerValue = values[lowerIndex] ?? 0;
        const upperValue = values[upperIndex] ?? lowerValue;
        return lowerValue + (upperValue - lowerValue) * mix;
    }

    Component.onCompleted: resetBarHeights()
    onEffectiveBarCountChanged: resetBarHeights()
    onShouldBindToAudioChanged: {
        if (!shouldBindToAudio)
            resetBarHeights();
    }

    Timer {
        id: fallbackTimer

        running: !(root.activeCavaService?.cavaAvailable ?? false) && shouldBindToAudio
        interval: 500
        repeat: true
        onTriggered: {
            const values = [];
            for (let i = 0; i < root.effectiveBarCount; i++)
                values.push(Math.random() * 25 + 5);
            root.activeCavaService.values = values;
        }
    }

    Connections {
        target: root.activeCavaService
        function onValuesChanged() {
            if (!root.shouldBindToAudio) {
                root.resetBarHeights();
                return;
            }

            const newHeights = [];
            const newPeaks = [];
            const newPeakTimes = [];
            const now = Date.now();
            for (let i = 0; i < root.effectiveBarCount; i++) {
                const rawLevel = root.sampledLevel(i);
                const previousHeight = root.barHeights[i] ?? root.minBarHeight;
                const previousPeak = root.peakHeights[i] ?? root.minBarHeight;
                const previousPeakTime = root.peakTimes[i] ?? 0;
                const clampedLevel = Math.max(0, Math.min(100, rawLevel));
                const normalizedLevel = clampedLevel / 100.0;
                const curvedLevel = normalizedLevel <= 0 ? 0 : Math.pow(normalizedLevel, Math.max(0.05, root.responseCurve));
                const targetHeight = root.minBarHeight + curvedLevel * root.heightRange;
                const smoothing = targetHeight >= previousHeight ? root.attackSmoothing : root.releaseSmoothing;
                const smoothedHeight = previousHeight + (targetHeight - previousHeight) * Math.max(0, Math.min(1, smoothing));

                if (rawLevel <= 0)
                    newHeights.push(root.minBarHeight);
                else if (rawLevel >= 100)
                    newHeights.push(root.maxBarHeight);
                else
                    newHeights.push(root.clampHeight(smoothedHeight));

                if (!root.peakHoldEnabled) {
                    newPeaks.push(newHeights[i]);
                    newPeakTimes.push(now);
                    continue;
                }

                if (newHeights[i] >= previousPeak) {
                    newPeaks.push(newHeights[i]);
                    newPeakTimes.push(now);
                } else if (now - previousPeakTime < root.peakHoldMs) {
                    newPeaks.push(previousPeak);
                    newPeakTimes.push(previousPeakTime);
                } else {
                    const droppedPeak = Math.max(newHeights[i], previousPeak - 1.5);
                    newPeaks.push(droppedPeak);
                    newPeakTimes.push(previousPeakTime);
                }
            }
            root.barHeights = newHeights;
            root.peakHeights = newPeaks;
            root.peakTimes = newPeakTimes;
        }
    }

    Item {
        anchors.centerIn: parent
        width: root.verticalMode ? 20 : root.contentSpan
        height: root.verticalMode ? root.contentSpan : 20

        Row {
            visible: !root.verticalMode
            anchors.centerIn: parent
            spacing: root.computedSpacing

            Repeater {
                model: root.effectiveBarCount

                Item {
                    width: root.computedBarWidth
                    height: 20

                    Rectangle {
                        width: parent.width
                        height: root.barHeights[index]
                        radius: 1.5
                        color: root.barColorAt(index)
                        y: root.effectiveVisualizerStyle === "bars" ? root.alignedY(height) : (20 - height) / 2
                        visible: root.effectiveVisualizerStyle === "bars"

                        Behavior on height {
                            enabled: root.shouldBindToAudio && !(root.activeCavaService?.cavaAvailable ?? false)
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.Linear
                            }
                        }
                    }

                    Rectangle {
                        visible: root.peakHoldEnabled
                        width: parent.width
                        height: 2
                        radius: 1
                        color: root.barColorAt(index)
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.effectiveVisualizerStyle === "bars" ? Math.max(0, root.alignedY(root.peakHeights[index] ?? root.minBarHeight) - 2) : Math.max(0, (parent.height - (root.peakHeights[index] ?? root.minBarHeight)) / 2)
                    }

                    Rectangle {
                        visible: root.effectiveVisualizerStyle === "lineWave"
                        width: Math.max(2, parent.width)
                        height: 2
                        radius: 1
                        color: root.barColorAt(index)
                        y: root.waveYAt(index)
                    }

                    Column {
                        visible: root.effectiveVisualizerStyle === "dottedParticles"
                        property int barIndex: index
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.alignedY(height)
                        spacing: 1
                        readonly property real dotSize: Math.max(2, Math.min(4, parent.width))
                        readonly property int dotCount: root.dottedBarCount(index)
                        width: dotSize
                        height: dotCount * dotSize + Math.max(0, dotCount - 1) * spacing

                        Repeater {
                            model: parent.dotCount

                            Rectangle {
                                required property int index
                                readonly property Item dotColumn: parent
                                readonly property real dotMix: root.effectiveBarCount <= 1 ? 0 : dotColumn.barIndex / Math.max(1, root.effectiveBarCount - 1)
                                width: dotColumn.width
                                height: dotColumn.dotSize
                                radius: dotColumn.dotSize / 2
                                color: root.gradientColorAtMix(dotMix)
                            }
                        }
                    }

                }
            }
        }

        Column {
            visible: root.verticalMode
            anchors.centerIn: parent
            spacing: root.computedSpacing

            Repeater {
                model: root.effectiveBarCount

                Item {
                    width: 20
                    height: root.computedBarWidth

                    Rectangle {
                        width: root.barHeights[index]
                        height: parent.height
                        radius: 1.5
                        color: root.barColorAt(index)
                        x: root.effectiveVisualizerStyle === "bars" ? root.alignedX(width) : (20 - width) / 2
                        visible: root.effectiveVisualizerStyle === "bars"

                        Behavior on width {
                            enabled: root.shouldBindToAudio && !(root.activeCavaService?.cavaAvailable ?? false)
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.Linear
                            }
                        }
                    }

                    Rectangle {
                        visible: root.peakHoldEnabled
                        width: 2
                        height: parent.height
                        radius: 1
                        color: root.barColorAt(index)
                        x: root.effectiveVisualizerStyle === "bars" ? Math.max(0, root.alignedX(root.peakHeights[index] ?? root.minBarHeight) - 2) : Math.max(0, (20 - (root.peakHeights[index] ?? root.minBarHeight)) / 2)
                    }

                    Rectangle {
                        visible: root.effectiveVisualizerStyle === "lineWave"
                        width: 2
                        height: Math.max(2, parent.height)
                        radius: 1
                        color: root.barColorAt(index)
                        x: root.waveYAt(index)
                    }

                    Row {
                        visible: root.effectiveVisualizerStyle === "dottedParticles"
                        property int barIndex: index
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.alignedX(width)
                        spacing: 1
                        readonly property real dotSize: Math.max(2, Math.min(4, parent.height))
                        readonly property int dotCount: root.dottedBarCount(index)
                        width: dotCount * dotSize + Math.max(0, dotCount - 1) * spacing
                        height: dotSize

                        Repeater {
                            model: parent.dotCount

                            Rectangle {
                                required property int index
                                readonly property Item dotRow: parent
                                readonly property real dotMix: root.effectiveBarCount <= 1 ? 0 : dotRow.barIndex / Math.max(1, root.effectiveBarCount - 1)
                                width: dotRow.dotSize
                                height: dotRow.height
                                radius: dotRow.height / 2
                                color: root.gradientColorAtMix(dotMix)
                            }
                        }
                    }

                }
            }
        }
    }
}
