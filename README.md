# 基于FPGA的术后视听交互终端

2026 年全国大学生嵌入式芯片与系统设计竞赛 FPGA 创新设计赛道作品代码。

**参赛选题：安路选题一——基于安路 EG4S20 的 HDMI 多媒体播放系统。**

本作品面向复苏室（PACU）与病房的术后视听交互场景，使用两块同款 HX4S20C 开发板，以 EG4S20BG256 为核心，通过自定义 UART 与 GPIO 链路协同运行。B 板执行业务流程、按键判定、计时、评分与报告存储；A 板执行 TF 读卡、图像解码、SDRAM 缓存、音频播放、字幕与 OSD，并通过 HDMI 输出图像和音频。运行时的控制和数据处理由 FPGA 逻辑完成。

## 1. 文件结构与工程入口

```text
作品代码/
├─ README.md
├─ master/                         B 业务主板
│  └─ src/
│     ├─ td_project/
│     │  └─ AnesthesiaRecovery_4Bank.al
│     └─ user_source/
│        ├─ hdl_source/             顶层、业务、通信、历史与 Flash 逻辑
│        └─ constraints_source/     引脚与时序约束
├─ media/                          A 媒体从板
│  └─ src/
│     ├─ td_project/                工程及音频等生成 IP
│     │  └─ AnesthesiaRecovery_4Bank.al
│     └─ user_source/
│        ├─ hdl_source/             媒体、显示、音频、OSD、字体及原厂 IP
│        └─ constraints_source/     引脚与时序约束
└─ TF_ROOT/                        50 张 BMP 与 50 个 PCM 运行素材
```

两份工程同名，顶层模块均为 `top`，顶层文件均为 `top_tf_hdmi_audio.v`。请根据所在目录区分 A、B 两板。工程所引用的头文件、加密核、生成 IP、ROM 初始化数据及工程排除项均按原配置保留；编译文件清单以各自 `.al` 为准。

## 2. 选题对应与实现功能

官方选题强调明确的多媒体应用场景、FPGA 内的自主控制与数据处理，以及核心功能完整性、显示稳定性、基础音频和工程规范性；允许同款 FPGA 多板协同。本作品结合上述方向，实现以下功能。

| 功能类别 | 本作品实现 |
|---|---|
| 图像读取与显示 | FAT32 根目录按短文件名查找 BMP；处理文件簇链；解码 640×480、24 位无压缩图像，经 SDRAM 和 HDMI 显示 |
| 帧缓存与切换 | 四个逻辑帧槽；完整帧加载后提交，在帧边界更新显示，协调取消、排空及缓存所有权 |
| 音频输出 | TF 裸 PCM 读取、FIFO 缓存、有效样本握手、音量处理与 I2S 输出，经 HDMI 嵌入音频 |
| 图层与字幕 | 中文字体、语音进度字幕、操作反馈、计时、参数、评分、历史与报告 OSD |
| 图片转场 | 淡出淡入及四方向 Wipe，配合帧边界参数锁存 |
| 实时调节 | 亮度、对比度、音量按档调节；OSD 显示当前参数 |
| 音频可视化 | 休息音乐页根据实际 I2S 音频幅值包络绘制双层叠山，属于时域包络显示 |
| 双板协作 | UART 可靠状态快照与 GPIO 实际呈现／播放完成反馈，业务计时与媒体输出分工 |

## 3. 应用流程

- **复苏室模式：**视听提示、呼叫应答、四肢活动记录与结果报告，提供最高 4 分的设备工程评分。
- **病房模式：**常识选择、视觉辨别、听觉应答、反应时间、按键保持及疼痛自述六项交互，形成最高 100 分的工程报告；题套按原题、A、B 顺序轮换。
- **独立练习：**按步骤进行操作教学，每步前三次错误可重试，第四次错误触发报警；练习流程与正式评分和报告记录独立。
- **宣教与休息：**四页宣教支持自动轮播和双向手动翻页，可切换休息音乐页。宣教页面实际呈现满 3000 ms 后发起下一页切换请求。复测等待为 30000 ms，从首张宣教实际呈现起算，到时提醒后由新的按键操作开始复测。
- **历史回看：**PACU 与病房共用最近 32 份记录，满后覆盖全局最旧记录；提供分类趋势、四卡摘要、详情以及用户 Flash 日志和上电恢复逻辑。

## 4. 核心代码导读

以下模块位于对应工程的 `src/user_source/hdl_source/recovery/`，顶层位于其上一级。

| 工程 | 模块 | 职责 |
|---|---|---|
| B | `recovery_assessment` | 模式、教学、测试、宣教与复测状态机 |
| B | `recovery_keys`、`recovery_cycle_to_ms` | 输入消抖、边沿资格、统一周期时间戳与毫秒换算 |
| B | `recovery_runtime_controls`、`recovery_ward_score` | 运行参数与病房工程评分 |
| B | `recovery_history_capture`、`recovery_report_history` | 报告快照、32 份记录、分类索引与趋势 |
| B | `recovery_flash_spi_master`、`recovery_report_flash_store` | 用户数据 Flash 读写及日志恢复 |
| B | `recovery_display_prep`、`recovery_master_bridge` | 低速显示字段准备与可靠业务快照发送 |
| A | `recovery_file_reader`、`recovery_bmp_decoder` | FAT32 文件读取及 BMP 检查与像素解码 |
| A | `frame_bank_manager`、`recovery_media_controller`、`recovery_frame_commit` | 帧槽、媒体调度及完整帧提交 |
| A | `recovery_pcm_player`、`recovery_pcm_volume` | PCM 缓冲、样本消费与音量 |
| A | `recovery_image_adjust`、`recovery_image_transition` | 亮度／对比度与转场 |
| A | `recovery_caption_practice_osd`、`recovery_result_osd`、`recovery_history_osd`、`recovery_runtime_osd` | 字幕、教学、结果、历史和运行参数图层 |
| A | `recovery_audio_visualizer`、`recovery_shared_geometry`、`recovery_shared_messages` | 音频包络与共享显示 ROM |
| A | `recovery_media_bridge`、`recovery_display_mailbox`、`recovery_pixel_ui_event` | 状态接收、跨域帧快照与呈现事件反馈 |
| 两板 | `recovery_uart_byte`、`recovery_uart_packet`、`recovery_uart_link` | UART 字节、帧协议、CRC16、序号／会话、确认重传、去重与心跳 |

`SD/`、`include/`、`IP/`、`hdmi1.4b_transmitter_core/` 等目录提供底层接口、SDRAM、视频、FIFO、PLL 与 HDMI 原厂实现。四帧槽按逻辑缓存区域进行管理。

## 5. 硬件连接与操作

用户操作接 B 板，媒体 TF 卡和 HDMI 显示／音频设备接 A 板。两板需共地，链路按 3.3 V LVCMOS 接口匹配；具体引脚以包内两份 `pin.adc` 和实际板卡接口为准。

| 连线 | A 板 | B 板 |
|---|---|---|
| A → B UART | TX：M14／J1.13 | RX：D16／J1.17 |
| B → A UART | RX：D16／J1.17 | TX：M14／J1.13 |
| PRESENTED | 输出 D14／J1.1 | 输入 D14／J1.1 |
| DONE | 输出 G11／J1.2 | 输入 G11／J1.2 |
| LINK_READY | 输出 G12／J1.3 | 输入 G12／J1.3 |
| 共地 | J1.12 或 J1.30 | J1.12 或 J1.30 |

UART 为 115200 波特率，传输场景与状态；图像和 PCM 由 A 板从本地 TF 卡读取。UART 确认与实际画面呈现分别处理，业务使用匹配的呈现反馈确定计时资格。

| B 板实体控件 | 功能 |
|---|---|
| KEY1（A2） | 翻转 SKIP 旁白等待选项 |
| KEY2（B2） | 随页面执行管理、返回或历史详情选择；宣教／休息互切；欢迎页长按 3 秒清除历史 |
| KEY4（C1） | 患者左键 L；调参时增加一档 |
| KEY3（B1） | 患者右键 R；调参时减少一档 |
| SW1（C8） | 单独拨上进入 PACU，拨下退出 |
| SW2（C7） | 单独拨上进入病房，拨下退出 |
| SW1＋SW2 | 均拨上进入历史回看 |
| SW3（C6） | 单独拨上调亮度 |
| SW4（C5） | 单独拨上调音量 |
| SW3＋SW4 | 均拨上调对比度 |

调参采用按次步进方式，每次新按改变一档；退出调参并释放双键后恢复患者答题。亮度范围 −64～+64、步长 8；对比度 128～384、步长 32，256 为单位增益；音量 0～256、步长 16。

## 6. TF 卡素材

`TF_ROOT/` 提供 50 张 BMP 图片与 50 段 PCM 音频。将其中全部文件直接复制到 FAT32 分区根目录，保留原文件名与完整素材集合，工程按场景与素材表完成图音匹配。

`EDUMOVE.PCM`、`EDUPAIN.PCM`、`EDUNAUS.PCM`、`EDUFOOD.PCM` 为四段宣教旁白，各为 288000 字节，对应标称 3 秒。
