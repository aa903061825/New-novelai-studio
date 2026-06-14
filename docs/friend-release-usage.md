# NAI CasRand / Novel Studio 朋友版使用说明

## 包内容

本次建议发两个压缩包：

- `NAI_CasRand-friend-windows-x64-*.zip`：Windows 应用本体。
- `NAI_CasRand-cache-translation-script-*.zip`：翻译缓存 + 剧本缓存，不包含素材库和原图。

另外，剧本原图目录请单独发，例如：

```text
E:\NAI的脚本群\作品集\NTR故事集
```

原图不需要和你电脑上完全同路径，但每个作品子文件夹的名字和里面的 JSON/PNG 文件名最好保持不变。

## 第一次使用

1. 解压应用包，进入包含 `NAI_CasRand.exe` 的文件夹。
2. 把缓存包也解压到同一个文件夹。
3. 解压后目录应类似：

```text
NAI_CasRand/
  NAI_CasRand.exe
  flutter_windows.dll
  data/
  bundled_cache/
    novel_studio/
      studio_manifest.json
      configs/
        trans_cache.json
        tag_classification_cache.json
      script_recast/
        knowledge.json
        cache/
          *.json
```

4. 双击 `NAI_CasRand.exe`。
5. 如果这是这台电脑第一次打开，程序会自动导入 `bundled_cache/novel_studio`。

## 已经打开过旧版本怎么办

如果朋友已经运行过软件，程序可能已经创建了自己的 workspace，此时不会再次自动导入缓存。

安全做法：

1. 关闭软件。
2. 打开：

```text
%APPDATA%\org.exception0x0194\nai3_autodraw
```

3. 把里面的 `novel_studio` 重命名成 `novel_studio_backup`。
4. 确认应用文件夹旁边有 `bundled_cache/novel_studio`。
5. 重新打开 `NAI_CasRand.exe`，程序会重新自动导入缓存。

如果朋友已经有自己的重要数据，不要直接覆盖 `novel_studio`，先备份。

## 剧本原图怎么放

原图目录可以单独解压到任意位置，例如：

```text
D:\NovelAI\NTR故事集
```

然后在软件的剧本 / Recast 页面里，选择某个作品子文件夹导入。现在程序会按作品目录名和帧文件名，把缓存里的旧图片路径重绑定到朋友电脑上的当前路径。

示例：

```text
你电脑旧路径：
E:\NAI的脚本群\作品集\NTR故事集\某个作品\nai_1.png

朋友电脑新路径：
D:\NovelAI\NTR故事集\某个作品\nai_1.png
```

只要 `某个作品` 目录名以及 `nai_1.png / nai_1.json` 这类文件名对应得上，缓存就能识别原图。

## 不发原图会怎样

只发缓存也能恢复一部分剧本分析、AI 草稿和映射状态，但原图预览、剧本馆封面、逐帧图片校对会缺失或显示不了。

所以推荐：

- 应用包：必须发。
- 缓存包：必须发。
- `NTR故事集` 原图包：想看图和继续校对就发。

## 注意

- 缓存包不包含 NovelAI API Token、账号密码或设置密钥。
- 素材库没有打包；角色/画师素材预览图不会随本缓存包一起发。
- 如果缓存导入后仍看不到图片，先确认导入的是作品子文件夹，而不是只导入了父级合集目录。
