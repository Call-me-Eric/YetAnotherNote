# YetAnotherPage

跨平台手写笔记。界面用 Flutter，笔迹用自有矢量格式，笔记目录以 `.yep` 结尾。各平台打开同一份笔记。不使用 PencilKit 保存或渲染笔迹。

产品约束在 [idea.md](idea.md)。还没做的阶段在 [schedule.md](schedule.md)。改代码前先看 [开发者手册](docs/developer.md)。

## 运行

SDK 约束见 `pubspec.yaml`（当前为 Dart 3.13）。

```bash
flutter pub get
flutter run
```

iOS 调试包从 `flutter run` 安装后启动。签名团队在 Xcode 里配置。

## 现在可以用

- 笔记库：新建、打开、重命名、删除。打开笔记时先完成读取，再进入页面。
- 页面：默认 A4（595.28 × 841.89 point），纵向排列。可以插入和删除页面。进入笔记时当前页居中。单指平移带惯性，双指缩放；缩放结束后按新比例重绘笔画瓦片。
- 图层：隐藏、锁定、调整上下顺序。
- 钢笔：鼠标和手写笔画在同一套画布上。抬笔后这条笔画的几何不再修改。已提交的笔画按瓦片绘制。
- 橡皮：对象橡皮擦掉整条笔画，区域橡皮擦掉经过的区域。
- 撤销和重做在一份笔记打开期间保留，换页不清空，关闭笔记后清空。
- Apple Pencil 悬停时显示笔尖或橡皮圆。捏侧面打开圆弧工具栏，可切换钢笔、文字、两种橡皮，以及撤销、重做。
- 文字框：在文字工具里长按并向右下拖动来创建。编辑时显示 Markdown 源码，失去焦点后渲染。公式写在 `$` 和 `$` 之间。框可以移动、缩放和删除；缩放只改变宽度并重排，不缩放字号。

## 还没做

荧光笔、中文组字、图片、图层合并、套索、PDF 导入、导出、文件夹和局域网同步。

## 笔记目录

一份笔记是目录包，不是压缩包。

```text
笔记名.yep/
  manifest.json
  pages/{page-id}/page.json
  pages/{page-id}/{layer-id}.json
  pages/{page-id}/strokes/{stroke-id}.json
  assets/{hash}
```

页面原点在左上角，y 向下。笔画、文字框都属于起始所在的那一页，超出部分裁掉。

## 许可

[Apache License 2.0](LICENSE)。
