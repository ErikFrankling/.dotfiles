import { App } from "astal/gtk3"
import style from "./style.scss"
import Bar from "./widget/Bar"
import NotificationPopups from "./notifications/NotificationPopups"

App.start({
    css: style,
    instanceName: "js",
    requestHandler(request, res) {
        print(request)
        res("ok")
    },
    // App.get_monitors().map(NotificationPopups),
    main: () => App.get_monitors().map(Bar).push(App.get_monitors().map(NotificationPopups)),
})
