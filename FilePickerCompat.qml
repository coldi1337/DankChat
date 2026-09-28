import QtQuick
import qs.Modals.FileBrowser

Loader {
    id: pickerHost
    objectName: "filePickerCompat"
    property string pickerTitle: ""
    property bool saveMode: false
    property string defaultFileName: ""
    property string implementation: ""
    property string loadError: ""
    property var componentErrors: []
    signal filesSelected(var paths)
    signal cancelled()

    function loadPicker() {
        // The stable FileBrowser import lets Quickshell register the host's
        // shared modules. Select the concrete type lazily across DMS versions.
        const candidates = [
            ["modern", "qs.DankCommon.FileBrowser", "FilePicker"],
            ["legacy", "qs.DankCommon.Modals.FileBrowser", "FileBrowserContent"],
            ["legacy", "qs.Modals.FileBrowser", "FileBrowserContent"]
        ];
        for (const candidate of candidates) {
            const properties = candidate[0] === "modern" ? `
                title: pickerHost.pickerTitle
                mode: pickerHost.saveMode ? "save" : "open"
                defaultName: pickerHost.defaultFileName
                bucket: pickerHost.saveMode ? "dankchat_export" : "dankchat_attachment"
                multiple: !pickerHost.saveMode
                filters: []
            ` : `
                browserTitle: pickerHost.pickerTitle
                saveMode: pickerHost.saveMode
                defaultFileName: pickerHost.defaultFileName
                browserType: pickerHost.saveMode ? "dankchat_export" : "dankchat_attachment"
                showSidebar: width >= 620
                fileExtensions: ["*"]
            `;
            try {
                const component = Qt.createQmlObject('import QtQuick\nimport ' + candidate[1] + ' as Native\nComponent { Native.' + candidate[2] + ' { ' + properties + ' } }', pickerHost, "DankChatFilePicker");
                implementation = candidate[0];
                sourceComponent = component;
                return;
            } catch (error) {
                componentErrors = componentErrors.concat([String(error)]);
            }
        }
        loadError = "No compatible file picker is available. Update DMS and run python3 scripts/check-environment.";
    }
    Component.onCompleted: loadPicker()
    onStatusChanged: if (status === Loader.Error) loadError = "No compatible file picker is available. Update DMS and run python3 scripts/check-environment.";
    onLoaded: {
        if (implementation === "legacy") item.initialize();
        item.forceActiveFocus();
    }
    Connections {
        target: pickerHost.item
        // The two host components intentionally have different signal names.
        ignoreUnknownSignals: true
        function onAccepted(paths) { pickerHost.filesSelected(paths); }
        function onRejected() { pickerHost.cancelled(); }
        function onFileSelected(path) { pickerHost.filesSelected([path.toString()]); }
        function onCloseRequested() { pickerHost.cancelled(); }
    }
}
