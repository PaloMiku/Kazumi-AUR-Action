# Maintainer: PaloMiku <palomiku@outlook.com>
pkgname=kazumi
pkgver=1.6.3
pkgrel=1
pkgdesc="从Kazumi仓库tar.gz文件构建，基于自定义规则的番剧采集APP，支持流媒体在线观看，支持弹幕。"
arch=('x86_64')
url='https://github.com/Predidit/Kazumi'
license=('GPL3')
source=("${pkgname}-${pkgver}.tar.gz::https://github.com/Predidit/Kazumi/releases/download/${pkgver}/Kazumi_linux_${pkgver}_amd64.tar.gz"
        "icon.png")
sha256sums=('SKIP' 'SKIP')
depends=('libayatana-appindicator' 'xdg-user-dirs' 'webkit2gtk-4.1')

package() {
    install -d "${pkgdir}/opt/Kazumi" "${pkgdir}/usr/bin"

    bsdtar -xf "$srcdir/${pkgname}-${pkgver}.tar.gz" -C "${pkgdir}/opt/Kazumi"

    ln -s /opt/Kazumi/kazumi "${pkgdir}/usr/bin/kazumi"

    install -Dm644 /dev/stdin "${pkgdir}/usr/share/applications/kazumi.desktop" <<EOF
#!/usr/bin/env xdg-open
[Desktop Entry]
Name=Kazumi
Comment=Watch Animes online with danmaku support.
Comment[zh_CN]=基于Flutter的自定义规则番剧采集与在线观看程序
Exec=kazumi
Icon=io.github.Predidit.Kazumi
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Video;
EOF

    install -Dm644 "${srcdir}/icon.png" "${pkgdir}/usr/share/icons/hicolor/128x128/apps/io.github.Predidit.Kazumi.png"
}
