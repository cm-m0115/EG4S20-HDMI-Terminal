# 基于双 EG4S20 的术后视听交互终端

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

官方选题强调明确的多媒体应用场景、FPGA 内的自主控制与数据处理，以及核心功能完整性、显示稳定性、基础音频和工程规范性；允许同款 FPGA 多板协同。下列格式与功能是本作品的实现选择，不将其另列为官方强制条款。

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

当前活动图像通路使用固定 640×480 解码，没有启用图片缩放。历史摘要卡由记录与字体绘制，不属于原图缩略图；音频叠山不执行 FFT 频谱分析。

## 3. 应用流程

- **复苏室模式：**视听提示、呼叫应答、四肢活动记录与结果报告，提供最高 4 分的设备工程评分。
- **病房模式：**常识选择、视觉辨别、听觉应答、反应时间、按键保持及疼痛自述六项交互，形成最高 100 分的工程报告；题套按原题、A、B 顺序轮换。
- **独立练习：**按步骤进行操作教学，每步前三次错误可重试，第四次错误触发报警；不计入正式评分，不占正式报告记录。
- **宣教与休息：**四页宣教支持自动轮播和双向手动翻页，可切换休息音乐页。自动轮播以每页实际呈现满 3000 ms 为下一页请求门槛，实际换图还包含读取、退役和转场时间。复测等待为 30000 ms，从首张宣教实际呈现起算，到时提醒后由新的按键操作开始复测。
- **历史回看：**PACU 与病房共用最近 32 份记录，满后覆盖全局最旧记录；提供分类趋势、四卡摘要、详情以及用户 Flash 日志和上电恢复逻辑。

评分与按键测试用于作品交互演示，不作为经过临床验证的医学量表或诊断结论。

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

`SD/`、`include/`、`IP/`、`hdmi1.4b_transmitter_core/` 等目录提供底层接口、SDRAM、视频、FIFO、PLL 与 HDMI 原厂实现。四帧槽是逻辑缓存区域，不等同于四个物理 SDRAM bank。

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

UART 为 115200 波特率，传输场景与状态，不传输图像像素或 PCM。UART 确认与实际画面呈现分别处理，业务使用匹配的呈现反馈确定计时资格。

| B 板实体控件 | 功能 |
|---|---|
| KEY1（A2） | 翻转 SKIP 旁白等待选项，不执行系统复位 |
| KEY2（B2） | 随页面执行管理、返回或历史详情选择；宣教／休息互切；欢迎页长按 3 秒清除历史 |
| KEY4（C1） | 患者左键 L；调参时增加一档 |
| KEY3（B1） | 患者右键 R；调参时减少一档 |
| SW1（C8） | 单独拨上进入 PACU，拨下退出 |
| SW2（C7） | 单独拨上进入病房，拨下退出 |
| SW1＋SW2 | 均拨上进入历史回看 |
| SW3（C6） | 单独拨上调亮度 |
| SW4（C5） | 单独拨上调音量 |
| SW3＋SW4 | 均拨上调对比度 |

调参每次新按改变一档，长按不连续改变；退出调参后双键全部释放才能恢复患者答题。亮度范围 −64～+64、步长 8；对比度 128～384、步长 32，256 为单位增益；音量 0～256、步长 16。参数仅当前通电会话有效。

## 6. TF 卡素材

将 `TF_ROOT/` 内的文件直接复制到 FAT32 分区根目录，不要将整个 `TF_ROOT` 文件夹再套入根目录。保留文件名和完整素材集合。

| 素材 | 支持格式 |
|---|---|
| BMP | 640×480、24 位、BI_RGB 无压缩、40 字节 DIB、正高度底向上 |
| PCM | 标称 48 kHz、16 位有符号小端、单声道裸采样，无 WAV 头；单声道输出到 HDMI 左右声道 |
| 文件名 | FAT 8.3 短文件名，按代码中的素材表匹配 |

`EDUMOVE.PCM`、`EDUPAIN.PCM`、`EDUNAUS.PCM`、`EDUFOOD.PCM` 各为 288000 字节，对应标称 3 秒。不要用 `_M` 别名代替这四个普通旁白文件。把 WAV 或 MP3 直接改名为 PCM 不能获得兼容素材。

## 7. 重新构建

环境：Windows，Anlogic TD 6.2.1 Engineer；工程记录版本为 `6.2.168116`，目标器件 `EG4S20BG256`。

1. 将整个提交目录复制或解压到较短的英文路径，例如 `D:/FPGA_Submission/`，保持 `master/`、`media/` 内部相对结构。原厂加密源加载涉及旧式路径处理，建议使用英文构建路径。
2. 用 TD 打开 `media/src/td_project/AnesthesiaRecovery_4Bank.al`，确认顶层 `top`、器件 `EG4S20BG256` 及包内源文件、IP、引脚和时序约束。
3. 沿工程原生默认流程（DefaultFlow）完成综合、实现与位流生成。
4. 对 `master/src/td_project/AnesthesiaRecovery_4Bank.al` 执行相同步骤，将生成结果明确区分为 A 媒体板和 B 业务板。
5. 使用同包两板工程的配对结果，连接板间链路、准备媒体 TF 卡，通过 A 板 HDMI 检查画面、声音和交互。

输入时钟 50 MHz；业务／读卡 100 MHz；A 板 SDRAM 40 MHz；视频像素时钟 25 MHz；HDMI 串行时钟 125 MHz。音频沿用工程中的 PLL 配置和名义 48 kHz 采样接口。请保留各时钟、刷新参数、生成 IP 与对应 SDC 的匹配配置。

本包提供源代码和配套媒体。本次整理检查覆盖依赖完整性、有效代码／约束一致性和文件打包，未重新执行 TD、RTL 仿真或板级验收。板级、配置 Flash 固化、冷启动、长稳及人工试听仍需实机确认；四段 3 秒旁白的字幕分句时间表也需结合实际声音复核。

## 8. 参考来源与版权

赛题依据：《全国大学生嵌入式芯片与系统设计竞赛 2026 FPGA 赛道选题指南——安路科技》，选题一见 PDF 第 14～15 页。

底层参考安路官方 `lab_ex5_i2s` 例程及 Anlogic HDMI、SDRAM、FIFO、PLL 等 IP；扩展设计参考 FPGA 创新设计赛道安路赛项完赛系列中的帧缓存、媒体读取、字幕、转场与参数控制思路，具体来源说明和厂商版权保留于相应文件。参考 IP 与材料的权利归原权利人所有，本包不对其另行授予许可。引用材料用于教育与竞赛展示，保留来源与版权声明，不用于商业培训。
