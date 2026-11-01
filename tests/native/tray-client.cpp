// Private native SNI/DBusMenu client. Qt owns the protocol implementation.
#include <QAction>
#include <QApplication>
#include <QFile>
#include <QMenu>
#include <QPixmap>
#include <QSystemTrayIcon>
#include <QTextStream>
#include <QTimer>

int main(int argc, char** argv) {
    QApplication app(argc, argv);
    app.setApplicationName("tray-native-fixture");
    app.setQuitOnLastWindowClosed(false);
    QFile log(argv[1]);
    if (!log.open(QIODevice::WriteOnly | QIODevice::Truncate)) return 2;
    QTextStream output(&log);
    auto add = [&](QMenu* menu, const QString& name) {
        auto* action = menu->addAction(name);
        QObject::connect(action, &QAction::triggered, [&, name](bool checked) {
            output << name << " " << checked << "\n";
            output.flush();
        });
        return action;
    };
    QMenu menu;
    add(&menu, "Action");
    add(&menu, "Disabled")->setEnabled(false);
    auto* check = add(&menu, "Check");
    check->setCheckable(true);
    menu.addSeparator();
    auto* submenu = menu.addMenu("Submenu");
    add(submenu, "Child");
    add(submenu, "Disabled child")->setEnabled(false);
    auto* asynchronous = menu.addMenu("Async");
    asynchronous->addAction("Waiting")->setEnabled(false);
    QObject::connect(check, &QAction::triggered, [&, asynchronous] {
        QTimer::singleShot(4000, [&, asynchronous] {
            asynchronous->clear();
            add(asynchronous, "Async child");
        });
    });
    auto* longMenu = menu.addMenu("Long list");
    for (int index = 0; index < 45; index++) add(longMenu, QString("Long %1").arg(index));
    QPixmap icon(32, 32);
    icon.fill(QColor("#7dcfff"));
    QSystemTrayIcon tray{QIcon(icon)};
    tray.setToolTip("Tray Regression Fixture");
    tray.setContextMenu(&menu);
    tray.show();
    QTimer::singleShot(45000, &app, &QApplication::quit);
    return app.exec();
}
