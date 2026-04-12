# JMcomic3-flutter 项目分析（中文）

## 1. 分析范围与统计
- 分析目录：`jasmine/lib`
- 代码规模：`107` 个 Dart 文件，约 `17,887` 行
- 页面文件：`28`（`lib/screens/*.dart`）
- 组件文件：`24`（`lib/screens/components/*.dart`）
- 配置文件：`45`（`lib/configs/*.dart`）
- 方法索引：自动提取约 `960` 项（含构造函数、生命周期方法、setter 等）

## 2. 项目定位与技术栈
- 项目定位：跨平台漫画浏览/阅读/下载应用
- 框架：Flutter（Material 3）
- 平台通道：`MethodChannel("methods")`（Dart ↔ 原生/后端能力）
- 状态与事件：`event` 包（如 `loginEvent`、`themeEvent`、`versionEvent`）
- 关键能力：登录鉴权、收藏评论、阅读器、下载导入导出、WebDAV 同步、版本更新、主题与阅读配置

## 3. 启动与主流程
1. `main.dart` 启动 `Jenny`，挂载 `MaterialApp`，主页进入 `InitScreen`。
2. `InitScreen._init()` 依次执行：
   - `methods.init()`
   - `initConfigs(context)`（加载全部配置）
   - 首次通过校验 `firstPassed()`
   - WebDAV 自动同步 `webDavSyncAuto(context)`
3. 按条件分流到：
   - `AuthScreen`（开启身份验证）
   - `FirstLoginScreen`（未配置登录）
   - `AppScreen`（主界面）
   - 失败兜底到 `NetworkSettingScreen`
4. `AppScreen` 由底部导航承载两大主分区：
   - 浏览（`BrowserScreenWrapper`）
   - 个人中心（`UserScreen`）

## 4. 功能清单（按业务模块）
- 启动与鉴权：初始化、首次通过检查、可选本地身份验证
- 登录体系：账号登录、游客模式、登录协议、JWT 访问保护
- 浏览发现：分类浏览、排序切换、每周必看、搜索历史
- 搜索能力：关键词检索、标签跳转检索、标题词过滤开关
- 漫画详情：作品信息、章节列表、评论、相关推荐、收藏切换
- 阅读器：多阅读模式（条漫/画廊/列表/双页）、方向与控件模式、手势与键盘、全屏、续读
- 下载管理：创建下载任务、章节下载状态、刷新/删除任务、线程数设置
- 导入导出：导入 `jm.zip/jmi/目录`，导出 `JMI/JM.ZIP/JPEGS.ZIP/CBZ/PDF/EPUB`
- 收藏系统：收藏夹拉取、创建、删除、重命名、作品移动
- 浏览记录：分页查看、单条删除、清空历史
- 评论系统：全站评论、我的评论、回复与子评论
- PRO/PAT：发电状态同步、CDKey 兑换、PAT 绑定与清理、线路选择
- 同步能力：WebDAV 开关、地址/账号/密码配置、上传/下载/双向同步
- 网络能力：API/CDN 节点选择与测速、代理配置
- 外观体验：主题、字号、屏幕方向、右键菜单、动画开关
- 阅读偏好：翻页方向、双页方向、滑块位置、显示 JM 代码、音量键控制
- 版本能力：自动/手动检查更新、更新公告读取、升级提醒
- 其他：图片预览与保存

## 5. 页面清单（`lib/screens/*.dart`）
| 页面类 | 文件 | 主要作用 | 关键方法 |
| --- | --- | --- | --- |
| `InitScreen` / `AuthScreen` | `lib/screens/init_screen.dart` | 启动初始化与身份验证分流 | `_init`、`test` |
| `FirstLoginScreen` | `lib/screens/first_login_screen.dart` | 首次登录/游客进入 | `_continueAsGuest`、`_form` |
| `AppScreen` | `lib/screens/app_screen.dart` | 主容器与底部导航 | `_onItemTapped`、`_buildBottomNavigationBar` |
| `BrowserScreen` | `lib/screens/browser_screen.dart` | 分类浏览、排序、搜索入口 | `_categories`、`_resort` |
| `WeekScreen` | `lib/screens/week_screen.dart` | 每周必看筛选与分页 | `_onPage`、`_switchToNextCategory` |
| `ComicSearchScreen` | `lib/screens/comic_search_screen.dart` | 关键词搜索结果页 | `buildScreen` |
| `ComicInfoScreen` | `lib/screens/comic_info_screen.dart` | 漫画详情、章节/评论/推荐 | `_buildTags`、`_changeFavourite` |
| `ComicReaderScreen` | `lib/screens/comic_reader_screen.dart` | 多模式阅读器 | `_load`、`_onChooseEp`、`_buildBar` |
| `ComicDownloadScreen` | `lib/screens/comic_download_screen.dart` | 章节勾选并创建下载 | `_buildButtons`、`_clickOfEp` |
| `DownloadsScreen` | `lib/screens/downloads_screen.dart` | 下载列表总览与管理 | `_load`、`_listView` |
| `DownloadAlbumScreen` | `lib/screens/download_album_screen.dart` | 单作品下载详情与本地续读 | `_buildContinueButton`、`_loadChapter` |
| `DownloadsExportScreen` | `lib/screens/downloads_exports_screen.dart` | 仅已完成任务的批量导出选择 | `_selectAllButton`、`_goToExport` |
| `DownloadsExportingScreen` | `lib/screens/downloads_exporting_screen.dart` | 执行批量导出流程 | `_exportJmis`、`_exportZips`、`_exportEpubs` |
| `DownloadsExportScreen2` | `lib/screens/downloads_exports_screen2.dart` | 含未完成任务的批量导出选择 | `_selectAllButton`、`_goToExport` |
| `DownloadsExportingScreen2` | `lib/screens/downloads_exporting_screen2.dart` | 执行导出（目录/PDF/EPUB） | `_exportJpegs`、`_exportPdf2`、`_exportEpub` |
| `DownloadImportScreen` | `lib/screens/download_import_screen.dart` | 导入下载包/目录 | `_fileImportButton`、`_importDirFilesZipButton` |
| `FavoritesScreen` | `lib/screens/favorites_screen.dart` | 收藏夹浏览（文件夹+排序） | `_chooseFolder`、`_chooseSort` |
| `ViewLogScreen` | `lib/screens/view_log_screen.dart` | 浏览记录查看与删除 | `buildScreen` |
| `CommentsScreen` | `lib/screens/comments_screen.dart` | 讨论区/我的评论 | `_body` |
| `UserScreen` | `lib/screens/user_screen.dart` | 个人中心与功能入口聚合 | `_buildCard`、`_buildFavorites`、`_buildSettingsIcon` |
| `SettingsScreen` | `lib/screens/settings_screen.dart` | 全局设置中心 | `buildScreen` |
| `AboutScreen` | `lib/screens/about_screen.dart` | 版本信息与更新内容 | `_buildNewestVersion`、`_buildVersionText` |
| `ProScreen` | `lib/screens/pro_screen.dart` | 发电中心（PAT/CDKey/绑定） | `patProWidgets`、`addPatAccount` |
| `ProOhScreen` | `lib/screens/pro_oh_screen.dart` | 非普通平台发电中心 | `buildScreen` |
| `AccessKeyReplaceScreen` | `lib/screens/access_key_replace_screen.dart` | PAT 密钥验证与绑定 | `_load`、`_bind`、`_save` |
| `NetworkSettingScreen` | `lib/screens/network_setting_screen.dart` | 网络配置与恢复入口 | `buildScreen` |
| `FilePhotoViewScreen` | `lib/screens/file_photo_view_screen.dart` | 图片预览与保存 | `buildScreen` |

## 6. 关键方法（核心网关）
核心业务接口集中在 `lib/basic/methods.dart` 的 `Methods`：
- 初始化/配置：`init`、`loadProperty`、`saveProperty`、`configLinks`
- 浏览搜索：`categories`、`comics`、`comicSearch`、`week`、`weekFilter`
- 漫画详情/阅读：`album`、`chapter`、`findViewLog`、`updateViewLog`
- 评论：`forum`、`comment`、`childComment`
- 收藏：`favorite`、`favorites`、`setFavorite`、收藏夹增删改与移动
- 下载：`allDownloads`、`downloadById`、`createDownload`、`dlImageByChapterId`、`deleteDownload`
- 导入导出：`import_jm_zip`、`import_jm_jmi`、`import_jm_dir`，以及多种 `export_*`
- PRO/PAT：`isPro`、`reloadPro`、`inputCdKey`、`checkPat`、`bindPatAccount`
- 网络/同步：`loadApiHost`、`saveApiHost`、`loadCdnHost`、`setProxy`、`webDavSync`
- 设备能力：`saveImageFileToGallery`、`androidGetVersion`、`iosGetDocumentDir` 等

## 7. 配置模块（`lib/configs`）
- 全量初始化入口：`initConfigs`（见 `lib/configs/configs.dart`）
- 主题与样式：`theme.dart`、`app_font_size.dart`
- 阅读设置：`reader_type.dart`、`reader_direction.dart`、`reader_controller_type.dart`、`two_page_direction.dart` 等
- 网络设置：`network_api_host.dart`、`network_cdn_host.dart`、`proxy.dart`
- 同步设置：`web_dav_*` 系列
- 登录与协议：`login.dart`
- 版本更新：`versions.dart`
- 其他：`auto_clean.dart`、`categories_sort.dart`、`search_title_words.dart`、`download_thread_count.dart` 等

## 8. 全量方法索引（自动提取）
说明：以下索引按文件列出，已尽量覆盖所有可识别方法（包含构造函数、生命周期方法、setter、私有方法）。

## lib/basic/commons.dart
类: (无)
方法:
- L100 saveImageFileToGallery
- L112 saveImageFileToFile
- L135 chooseSortBy
- L140 add0
- L149 openUrl
- L160 displayTextInputDialog
- L18 defaultToast
- L221 copyToClipBoard
- L227 confirmDialog
- L259 confirmCopy
- L266 chooseFolder
- L83 androidGalleryPermissionRequest
- L90 androidMangeStorageRequest

## lib/basic/desktop.dart
类: WinListener
方法:
- L13 onDesktopStop
- L25 onWindowResize
- L29 saveSize
- L6 onDesktopStart

## lib/basic/entities.dart
类: SortBy, Page, CountPage, SearchPage, ComicsResponse, ComicSimple, ComicSimpleCategory, CategoriesResponse, Categories, Block, AlbumResponse, Series, ComicBasic, ChapterResponse, ImageSize, Comment, Expinfo, Badge, CommentPage, PreLoginResponse, SelfInfo, FavoriteFolder, Favorite, FavoriteFolderItem, FavoritesResponse, WeekFilterResponse, ActionResponse, InnerComicPage, CommentResponse, ViewLog, GamePage, Game, GameCategory, SearchHistory, DownloadCreate, DownloadCreateAlbum, DownloadCreateChapter, DownloadAlbum, DlImage, IsPro, ProInfoAll, ProInfoAf, ProInfoPat, WeekData, WeekCategory, WeekType
方法:
- L10 toString
- L1009 toJson
- L103 ComicSimple
- L1043 toJson
- L1065 toJson
- L1089 toJson
- L1123 toJson
- L1152 toJson
- L1202 toJson
- L1251 toJson
- L1265 albumToSimple
- L127 toJson
- L149 toJson
- L173 toJson
- L204 toJson
- L229 toJson
- L292 toJson
- L330 toJson
- L362 toJson
- L405 toJson
- L433 toJson
- L48 toJson
- L500 toJson
- L55 CountPage
- L551 toJson
- L581 toJson
- L621 toJson
- L693 toJson
- L734 toJson
- L753 toJson
- L760 Favorite
- L77 toJson
- L783 toJson
- L798 toJson
- L829 toJson
- L873 toJson
- L913 toJson
- L949 toJson
- L95 toJson

## lib/basic/http_client.dart
类: AppHttpClient
方法:
- L14 getText
- L71 getTextOrNull

## lib/basic/log.dart
类: (无)
方法:
- L3 debugPrient

## lib/basic/methods.dart
类: Methods, _Response
方法:
- L100 saveImageFileToGallery
- L104 saveProperty
- L108 album
- L115 chapter
- L119 forum
- L128 favorites
- L138 favorite
- L144 setFavorite
- L150 createFavoriteFolder
- L154 deleteFavoriteFolder
- L158 comicFavoriteFolderMove
- L162 renameFavoriteFolder
- L166 games
- L172 updateViewLog
- L180 findViewLog
- L188 cleanAllCache
- L19 _invoke
- L192 jm3x4Cover
- L196 jmSquareCover
- L200 jmPageImage
- L204 jmPhotoImage
- L208 imageSize
- L212 httpGet
- L216 loadApiHost
- L220 loadCdnHost
- L224 saveApiHost
- L228 saveCdnHost
- L232 preLogin
- L238 login
- L247 logout
- L251 commentResponse
- L258 comment
- L265 childComment
- L277 loadUsername
- L281 loadLastLoginUsername
- L285 loadPassword
- L289 clearViewLog
- L293 lastSearchHistories
- L301 allDownloads
- L309 downloadById
- L318 createDownload
- L323 dlImageByChapterId
- L330 deleteDownload
- L334 renewAllDownloads
- L339 loadAndroidModes
- L346 setAndroidMode
- L352 androidGetVersion
- L359 export_jm_jpegs
- L367 export_jm_zip
- L375 export_jm_zip_single
- L385 export_jm_jpegs_zip_single
- L395 export_jm_jmi
- L403 export_jm_jmi_single
- L413 export_cbzs_zip_single
- L423 export_jm_pdf
- L431 export_jm_pdf2
- L439 export_jm_epub
- L447 export_jm_epub_single
- L457 import_jm_zip
- L46 init
- L462 import_jm_jmi
- L467 import_jm_dir
- L472 isPro
- L476 proInfoAll
- L480 reloadPro
- L484 inputCdKey
- L488 checkPat
- L492 bindPatAccount
- L50 configLinks
- L501 reloadPatAccount
- L505 clearPat
- L509 load_download_thread
- L513 set_download_thread
- L517 clearAllSearchLog
- L521 clearASearchLog
- L525 setProxy
- L529 getProxy
- L533 webDavSync
- L537 iosGetDocumentDir
- L541 androidDefaultExportsDir
- L545 getDownloadAndExportTo
- L549 getHomeDir
- L553 setDownloadAndExportTo
- L557 ping
- L562 pingCdn
- L567 mkdirs
- L571 androidMkdirs
- L575 picturesDir
- L579 copyPictureToFolder
- L589 getProServerName
- L59 loadProperty
- L593 setProServerName
- L597 verifyAuthentication
- L601 daily
- L605 week
- L611 weekFilter
- L63 comics
- L72 comicSearch
- L85 pageViewLog
- L90 deleteViewLogByComicId
- L95 categories

## lib/basic/web_dav_sync.dart
类: (无)
方法:
- L12 webDavSync
- L27 webDavSyncUpload
- L42 webDavSyncDownload
- L57 webDavSyncAuto
- L65 webDavSyncClick
- L80 webDavSyncUploadClick
- L95 webDavSyncDownloadClick

## lib/configs/android_display_mode.dart
类: (无)
方法:
- L15 initAndroidDisplayMode
- L23 _changeMode
- L27 _chooseAndroidDisplayMode
- L44 androidDisplayModeSetting

## lib/configs/android_version.dart
类: (无)
方法:
- L7 initAndroidVersion

## lib/configs/app_font_size.dart
类: (无)
方法:
- L17 initFontSizeAdjust
- L27 currentFontSizeAdjust
- L31 fontSizeAdjustSettings
- L37 fontSizeAdjustSetting

## lib/configs/app_orientation.dart
类: (无)
方法:
- L15 appOrientationName
- L29 initAppOrientation
- L34 _fromString
- L45 chooseAppOrientation
- L62 appOrientationWidget
- L80 _set

## lib/configs/Authentication.dart
类: (无)
方法:
- L13 initAuthentication
- L25 currentAuthentication
- L29 verifyAuthentication
- L41 authenticationSetting
- L73 _chooseAuthentication

## lib/configs/auto_clean.dart
类: CacheCleanResult
方法:
- L105 cleanCache
- L129 _autoCleanSeconds
- L133 _nowSeconds
- L137 _loadLastCleanTs
- L142 _saveLastCleanTs
- L146 _parseInt
- L39 initAutoClean
- L51 autoCleanName
- L55 chooseAutoClean
- L79 runAutoCleanIfNeeded

## lib/configs/categories_sort.dart
类: CategoriesSortScreen, _CategoriesSortScreenState, CategoriesSortPanel, _CategoriesSortPanelState
方法:
- L11 sortCategories
- L130 CategoriesSortPanel
- L133 createState
- L139 _switch
- L150 build
- L203 _wrapItems
- L210 append
- L305 _saveIcon
- L33 getCategoriesSort
- L39 initCategoriesSort
- L50 saveCategoriesSort
- L56 categoriesSortSetting
- L72 CategoriesSortScreen
- L75 createState
- L83 initState
- L88 build

## lib/configs/configs.dart
类: (无)
方法:
- L48 initConfigs

## lib/configs/daily_sign.dart
类: (无)
方法:
- L19 _setDailySignStatus
- L24 dailySignStatusLabel
- L38 checkDailySignStatus

## lib/configs/DesktopAuthenticationScreen.dart
类: VerifyPassword, _VerifyPasswordState, SetPassword, _SetPasswordState
方法:
- L11 VerifyPassword
- L14 createState
- L21 build
- L58 SetPassword
- L6 needDesktopAuthentication
- L61 createState
- L69 build

## lib/configs/disable_recommend_content.dart
类: (无)
方法:
- L12 initDisableRecommendContent
- L20 currentDisableRecommendContent
- L24 disableRecommendContentSetting

## lib/configs/display_jmcode.dart
类: (无)
方法:
- L13 initDisplayJmcode
- L21 currentDisplayJmcode
- L25 _chooseDisplayJmcode
- L35 displayJmcodeSetting

## lib/configs/download_and_export_to.dart
类: (无)
方法:
- L14 initDownloadAndExportTo
- L19 currentDownloadAndExportToName
- L27 downloadAndExportToSetting

## lib/configs/download_thread_count.dart
类: (无)
方法:
- L13 initDownloadThreadCount
- L17 downloadThreadCountSetting
- L37 chooseDownloadThread

## lib/configs/export_path.dart
类: (无)
方法:
- L107 chooseEx
- L14 initExportPath
- L35 showExportPath
- L42 _setExportPath
- L47 displayExportPathInfo
- L89 attachExportPath

## lib/configs/export_rename.dart
类: (无)
方法:
- L10 initExportRename
- L14 currentExportRename
- L18 _chooseExportRename
- L28 exportRenameSetting

## lib/configs/ignore_upgrade_pop.dart
类: (无)
方法:
- L10 initIgnoreUpgradePop
- L17 currentIgnoreUpgradePop
- L21 ignoreUpgradePopSetting

## lib/configs/ignore_view_log.dart
类: (无)
方法:
- L13 initIgnoreVewLog
- L17 currentIgnoreVewLog
- L21 ignoreVewLogSetting

## lib/configs/import_notice.dart
类: (无)
方法:
- L5 importNotice

## lib/configs/is_pro.dart
类: (无)
方法:
- L27 reloadIsPro

## lib/configs/login.dart
类: LoginAgreementHint, _LoginAgreementSheet, _LoginDialog, _LoginDialogState
方法:
- L112 renameFavoriteFolderItemTile
- L142 fav
- L151 login
- L167 enterGuestMode
- L174 ensureJwtAccess
- L212 loginDialog
- L228 showLoginAgreementBottomSheet
- L241 showUserAgreementBottomSheet
- L245 userAgreementSetting
- L262 build
- L291 build
- L36 _loginState
- L381 createState
- L389 initState
- L402 build
- L41 initLogin
- L68 createFavoriteFolderItemTile
- L87 deleteFavoriteFolderItemTile

## lib/configs/network_api_host.dart
类: ApiOptionRow, _ApiOptionRowState, PingStatus
方法:
- L108 _fetchApiDomainList
- L126 _httpGetText
- L134 _stripNonAsciiPrefix
- L146 _decodeDomainServerData
- L154 _md5HexBytes
- L159 _aesEcbDecrypt
- L170 _pkcs7UnpadToString
- L220 _manualInputApiHost
- L255 ApiOptionRow
- L258 createState
- L265 initState
- L271 build
- L32 initApiHost
- L322 PingStatus
- L325 build
- L340 chooseApiHost
- L348 apiHostSetting
- L45 _decodeBase64List
- L52 _loadCachedApiList
- L67 _refreshApiListIfNeeded
- L83 _mergeApiList
- L94 _fetchLatestApiDomainList

## lib/configs/network_cdn_host.dart
类: CdnOptionRow, _CdnOptionRowState, PingStatus
方法:
- L107 _manualInputApiHost
- L142 CdnOptionRow
- L145 createState
- L152 initState
- L158 build
- L219 PingStatus
- L222 build
- L29 initCdnHost
- L36 chooseCdnHost
- L44 cdnHostSetting
- L8 _truncateLabel

## lib/configs/no_animation.dart
类: (无)
方法:
- L13 initNoAnimation
- L17 currentNoAnimation
- L21 _chooseNoAnimation
- L31 noAnimationSetting

## lib/configs/pager_column_number.dart
类: (无)
方法:
- L12 initPagerColumnCount
- L20 choosePagerColumnCount

## lib/configs/pager_controller_mode.dart
类: (无)
方法:
- L24 choosePagerControllerMode
- L35 _parse
- L44 initPagerControllerMode

## lib/configs/pager_cover_rate.dart
类: (无)
方法:
- L17 initPagerCoverRate
- L21 _fromString
- L30 pagerCoverRateName
- L39 choosePagerCoverRate

## lib/configs/pager_view_mode.dart
类: (无)
方法:
- L28 choosePagerViewMode
- L39 _parse
- L48 initPagerViewMode

## lib/configs/passed.dart
类: (无)
方法:
- L13 initPassed
- L17 currentPassed
- L21 firstPassed

## lib/configs/proxy.dart
类: (无)
方法:
- L10 initProxy
- L15 currentProxyName
- L19 inputProxy
- L33 proxySetting

## lib/configs/reader_controller_type.dart
类: (无)
方法:
- L27 initReaderControllerType
- L36 _readerControllerTypeFromString
- L45 currentReaderControllerTypeName
- L54 chooseReaderControllerType

## lib/configs/reader_direction.dart
类: (无)
方法:
- L14 initReaderDirection
- L18 _fromString
- L29 readerDirectionName
- L40 chooseReaderDirection

## lib/configs/reader_slider_position.dart
类: (无)
方法:
- L20 initReaderSliderPosition
- L26 _readerSliderPositionFromString
- L38 chooseReaderSliderPosition

## lib/configs/reader_type.dart
类: (无)
方法:
- L15 initReaderType
- L19 _fromString
- L30 readerTypeName
- L43 chooseReaderType

## lib/configs/recommend_links.dart
类: (无)
方法:
- L11 initRecommendLinks
- L21 _replaceFollowChannelLink
- L9 currentRecommendLinks

## lib/configs/search_title_words.dart
类: (无)
方法:
- L13 initSearchTitleWords
- L21 currentSearchTitleWords
- L25 _chooseSearchTitleWords
- L35 searchTitleWordsSetting

## lib/configs/theme.dart
类: (无)
方法:
- L231 _buildTextTheme
- L290 initTheme
- L303 themeName
- L307 chooseTheme
- L319 reloadBarColor
- L323 _reloadBarColor
- L347 themeSetting
- L37 _buildAppTheme

## lib/configs/two_page_direction.dart
类: (无)
方法:
- L13 initTwoPageDirection
- L17 _fromString
- L28 twoPageDirectionName
- L37 chooseTwoPageDirection
- L53 twoGalleryDirectionSetting

## lib/configs/using_right_click_pop.dart
类: (无)
方法:
- L13 initUsingRightClickPop
- L17 currentUsingRightClickPop
- L21 usingRightClickPopSetting

## lib/configs/versions.dart
类: TopConfirm
方法:
- L104 manualCheckNewVersion
- L114 silentCheckNewVersion
- L118 dirtyVersion
- L122 _versionCheck
- L156 _pickLatestVersion
- L169 _fetchLatestReleaseJson
- L200 _httpGetViaDart
- L213 _fetchLatestReleaseInfoFromPage
- L227 _extractReleaseBodyFromPage
- L285 _isRateLimitError
- L291 _decodeHtmlEntities
- L300 _periodText
- L313 _choosePeriod
- L355 autoUpdateCheckSetting
- L370 formatDateTimeToDateTime
- L380 versionPop
- L392 topConfirm
- L44 initVersion
- L85 currentVersion
- L93 latestVersionInfo
- L97 autoCheckNewVersion

## lib/configs/volume_key_control.dart
类: (无)
方法:
- L13 initVolumeKeyControl
- L17 currentVolumeKeyControl
- L21 _chooseVolumeKeyControl
- L31 volumeKeyControlSetting

## lib/configs/web_dav_password.dart
类: (无)
方法:
- L11 initWebDavPassword
- L16 currentWebDavPasswordName
- L20 inputWebDavPassword
- L33 webDavPasswordSetting

## lib/configs/web_dav_sync_switch.dart
类: (无)
方法:
- L10 initWebDavSyncSwitch
- L14 currentWebDavSyncSwitch
- L18 _chooseWebDavSyncSwitch
- L28 webDavSyncSwitchSetting

## lib/configs/web_dav_url.dart
类: (无)
方法:
- L17 currentWebDavUrlName
- L23 inputWebDavUrl
- L37 webDavUrlSetting
- L9 initWebDavUrl

## lib/configs/web_dav_username.dart
类: (无)
方法:
- L11 initWebDavUserName
- L16 currentWebDavUserNameName
- L20 inputWebDavUserName
- L33 webDavUserNameSetting

## lib/main.dart
类: Jenny, _JennyState
方法:
- L13 Jenny
- L16 createState
- L21 initState
- L28 dispose
- L34 _setState
- L39 build
- L8 main

## lib/screens/about_screen.dart
类: AboutScreen, _AboutState
方法:
- L100 _buildCurrentVersion
- L107 _buildNewestVersion
- L120 _buildNewestVersionSpan
- L135 _buildCheckButton
- L15 AboutScreen
- L151 _buildGotoGithub
- L166 _buildVersionText
- L18 createState
- L25 initState
- L37 build
- L41 buildScreen
- L63 _buildLogo

## lib/screens/access_key_replace_screen.dart
类: AccessKeyReplaceScreen, _AccessKeyReplaceScreenState
方法:
- L12 AccessKeyReplaceScreen
- L136 _bind
- L149 _save
- L16 createState
- L29 initState
- L34 _load
- L58 build
- L62 buildScreen

## lib/screens/app_screen.dart
类: AppScreen, _AppScreenState, AppScreenData
方法:
- L13 AppScreen
- L16 createState
- L38 initState
- L48 dispose
- L54 _versionSub
- L61 _onItemTapped
- L71 build
- L96 _buildBottomNavigationBar

## lib/screens/browser_screen.dart
类: BrowserScreenWrapper, _BrowserScreenWrapperState, BrowserScreen, _BrowserScreenState, _MTabBar, _MTabBarState
方法:
- L107 dispose
- L112 _resort
- L120 build
- L21 BrowserScreenWrapper
- L213 createState
- L222 dispose
- L228 build
- L25 createState
- L30 initState
- L36 dispose
- L41 _setState
- L46 build
- L74 BrowserScreen
- L78 createState
- L91 _categories
- L99 initState

## lib/screens/comic_download_screen.dart
类: ComicDownloadScreen, _ComicDownloadScreenState
方法:
- L11 ComicDownloadScreen
- L14 createState
- L150 _buildSeries
- L180 _clickOfEp
- L195 _colorOfEp
- L207 _iconOfEp
- L219 _textColorOfEp
- L22 _init
- L28 initState
- L34 build
- L38 buildScreen
- L81 _buildButtons

## lib/screens/comic_info_screen.dart
类: ComicInfoScreen, _ComicInfoScreenState, _ComicSerials, _ComicSerialsState, _ComicRelatedList, _ComicRelatedListState
方法:
- L227 _buildTags
- L23 ComicInfoScreen
- L27 createState
- L283 _changeFavourite
- L327 createState
- L332 build
- L346 _buildOneButton
- L360 _buildSeries
- L364 _buildSeriesWrap
- L397 _buildSeriesList
- L40 didChangeDependencies
- L427 _push
- L447 _onChoose
- L46 didPopNext
- L463 createState
- L472 build
- L53 dispose
- L59 build
- L63 buildScreen

## lib/screens/comic_reader_screen.dart
类: ComicReaderScreen, _ComicReaderScreenState, _ReaderControllerEventArgs, _ComicReader, _EpChooser, _EpChooserState, _SettingPanel, _SettingPanelState, _ComicReaderWebToonState, _ComicReaderGalleryState, _ListViewReaderState, _TwoPageGalleryReaderState
方法:
- L1026 _bottomIcon
- L1071 initState
- L1082 dispose
- L1087 _onListCurrentChange
- L1105 _renderSizeFor
- L1129 _onTrueSize
- L1145 _needJumpTo
- L1163 _buildViewer
- L1172 _buildList
- L1214 _buildNextEp
- L1244 initState
- L1250 _reloadImage
- L1263 _buildGallery
- L1327 dispose
- L1333 _buildViewer
- L1351 _needJumpTo
- L1364 _onGalleryPageChange
- L1377 _preloadJump
- L1378 fn
- L1394 _buildNextEpController
- L1447 initState
- L1465 dispose
- L1474 _onTransformChanged
- L1484 _onScrollChanged
- L1504 _onPointerDown
- L1513 _onPointerEnd
- L1523 _needJumpTo
- L1568 _buildViewer
- L1577 _renderSizeFor
- L1602 _onTrueSize
- L1617 _buildList
- L165 _onVolumeEvent
- L1688 _buildNextEp
- L1711 _handleDoubleTapDown
- L1715 _handleDoubleTap
- L172 addVolumeListen
- L1746 initState
- L1765 _buildView
- L1778 _buildOptions
- L180 delVolumeListen
- L187 readerKeyboardHolder
- L1891 _reloadImage
- L1907 dispose
- L1913 _needJumpTo
- L1928 _preloadJump
- L1929 fn
- L1945 _buildViewer
- L1956 _onGalleryPageChange
- L1969 _buildNextEpController
- L230 _ComicReader
- L244 createState
- L272 _persistViewLog
- L284 _schedulePersistViewLog
- L293 _flushViewLogPersist
- L302 _rebuildSeriesCache
- L321 _onFullScreenChange
- L340 _onCurrentChange
- L352 initState
- L37 ComicReaderScreen
- L373 didUpdateWidget
- L381 dispose
- L397 _onPageControl
- L416 build
- L462 _sliderDraggingText
- L48 createState
- L481 _buildFullScreenControllerStackItem
- L551 _buildTouchOnceControllerAction
- L56 _load
- L561 _buildTouchDoubleControllerAction
- L571 _buildTouchDoubleOnceNextControllerAction
- L584 _buildThreeAreaControllerAction
- L647 _buildBar
- L65 initState
- L726 _buildAppBar
- L742 _buildSliderBottom
- L755 _buildSliderLeft
- L780 _buildSliderRight
- L805 _buildSliderWidget
- L82 build
- L848 _onChooseEp
- L86 buildScreen
- L862 _onMoreSetting
- L882 _appBarHeight
- L886 _bottomBarHeight
- L890 _fullscreenController
- L905 _hasNextEp
- L909 _onNextAction
- L926 createState
- L931 build
- L978 createState
- L983 build

## lib/screens/comic_search_screen.dart
类: ComicSearchScreen, _ComicSearchScreenState
方法:
- L14 ComicSearchScreen
- L18 createState
- L27 build
- L31 buildScreen

## lib/screens/comments_screen.dart
类: CommentsScreen, _CommentsScreenState, SelfCommentList, _SelfCommentListState
方法:
- L100 build
- L11 createState
- L20 initState
- L26 dispose
- L32 build
- L36 buildScreen
- L45 _body
- L74 SelfCommentList
- L77 createState
- L8 CommentsScreen
- L82 initState
- L88 dispose
- L93 _setState

## lib/screens/components/actions.dart
类: (无)
方法:
- L5 buildOrderSwitch

## lib/screens/components/avatar.dart
类: Avatar
方法:
- L12 Avatar
- L15 build

## lib/screens/components/badge.dart
类: Badged, VersionBadged, _VersionBadgedState
方法:
- L12 build
- L49 VersionBadged
- L52 createState
- L57 initState
- L63 dispose
- L68 _onVersion
- L73 build
- L9 Badged

## lib/screens/components/browser_bottom_sheet.dart
类: BrowserBottomSheetAction, _BrowserBottomSheet, _BrowserBottomSheetState
方法:
- L17 build
- L186 _bottomIcon
- L27 _displayBrowserBottomSheet
- L44 createState
- L53 initState
- L60 dispose
- L66 _setState
- L70 _runManualClean
- L94 build

## lib/screens/components/comic_comments_list.dart
类: ComicCommentsList, _ComicCommentsListState, _ComicCommentItem, _ComicCommentItemState, _CommentChildrenScreen, _CommentChildrenScreenState
方法:
- L102 _buildPrePage
- L122 _buildNextPage
- L143 _buildComment
- L176 _buildPostComment
- L20 ComicCommentsList
- L239 createState
- L246 build
- L29 createState
- L37 _loadPage
- L460 parseCommentBody
- L492 _CommentChildrenScreen
- L500 createState
- L505 build
- L51 initState
- L57 build

## lib/screens/components/comic_download_card.dart
类: ComicDownloadCard
方法:
- L109 _c
- L11 ComicDownloadCard
- L120 _author
- L17 build
- L96 _buildCategoryRow

## lib/screens/components/comic_floating_search_bar.dart
类: ComicFloatingSearchBarScreen, _ComicFloatingSearchBarScreenState
方法:
- L13 blockStore
- L163 _buildTags
- L19 searchHistories
- L213 _buildTitle
- L245 _buildSubTitle
- L30 ComicFloatingSearchBarScreen
- L38 createState
- L46 initState
- L52 dispose
- L58 _setState
- L63 build
- L72 _onSubmitted
- L79 _buildPanel
- L90 _buildHistory

## lib/screens/components/comic_info_card.dart
类: ComicInfoCard
方法:
- L120 _buildCategoryRow
- L133 _c
- L143 titleProcess
- L15 ComicInfoCard
- L22 build

## lib/screens/components/comic_list.dart
类: ComicList, _ComicListState
方法:
- L142 _buildInfoMode
- L168 _buildTitleInCoverMode
- L21 ComicList
- L267 _buildTitleAndCoverMode
- L32 createState
- L361 _pushToComicInfo
- L367 _wrapWithScrollListener
- L37 initState
- L380 _longPressCallback
- L403 _longPressImageCallback
- L45 dispose
- L52 _setState
- L57 build
- L70 _buildCoverMode

## lib/screens/components/comic_pager.dart
类: ComicPager, _ComicPagerState, _StreamPager, _StreamPagerState, _PagerPager, _PagerPagerState
方法:
- L101 _join
- L151 _jumpPage
- L18 _calcMaxPage
- L207 initState
- L216 dispose
- L224 _onScroll
- L237 _buildLoadingCard
- L291 build
- L30 ComicPager
- L313 _buildPagerBar
- L346 _setState
- L356 _PagerPager
- L364 createState
- L375 _load
- L38 createState
- L392 initState
- L397 dispose
- L403 build
- L424 _buildPagerBar
- L43 initState
- L49 dispose
- L54 _setState
- L542 _redirectAid
- L59 build
- L80 _StreamPager
- L88 createState

## lib/screens/components/content_builder.dart
类: ContentBuilder
方法:
- L21 build

## lib/screens/components/content_error.dart
类: ContentError
方法:
- L10 ContentError
- L18 build

## lib/screens/components/content_loading.dart
类: ContentLoading
方法:
- L6 ContentLoading
- L9 build

## lib/screens/components/continue_read_button.dart
类: ContinueReadButton, _ContinueReadButtonState
方法:
- L12 ContinueReadButton
- L20 createState
- L25 build

## lib/screens/components/error_types.dart
类: (无)
方法:
- L7 errorType

## lib/screens/components/floating_search_bar.dart
类: FloatingSearchBarScreen, _FloatingSearchBarScreenState, _SearchBarContainer, FloatingSearchBarController
方法:
- L108 _buildSearchBar
- L12 FloatingSearchBarScreen
- L184 _buildTextField
- L215 _displayFloatingSearchBar
- L223 _hideSearchBar
- L232 _SearchBarContainer
- L235 build
- L24 createState
- L262 hide
- L264 display
- L39 initState
- L45 dispose
- L53 build
- L70 _buildOnPop
- L83 _buildBackdrop

## lib/screens/components/images.dart
类: JM3x4ImageProvider, PageImageProvider, JM3x4Cover, _JM3x4CoverState, JMSquareCover, _JMSquareCoverState, JMPhotoImage, _JMPhotoImageState, JMPageImage, _JMPageImageState
方法:
- L106 loadImage
- L117 obtainKey
- L156 toString
- L166 _pageImageCacheKey
- L168 _cachedPageImagePath
- L183 _cachedPageImageTrueSize
- L203 _evictPageImageCache
- L217 JM3x4Cover
- L227 createState
- L23 loadBuffer
- L234 initState
- L240 build
- L260 JMSquareCover
- L270 createState
- L277 initState
- L283 build
- L302 JMPhotoImage
- L311 createState
- L318 initState
- L324 build
- L34 loadImage
- L343 JMPageImage
- L348 createState
- L356 initState
- L361 _init
- L374 _reload
- L394 build
- L414 pathFutureImage
- L45 obtainKey
- L460 buildSvg
- L478 buildMock
- L495 buildError
- L548 buildLoading
- L586 buildFile
- L80 toString
- L95 loadBuffer

## lib/screens/components/item_builder.dart
类: ItemBuilder
方法:
- L12 ItemBuilder
- L22 build

## lib/screens/components/my_flat_button.dart
类: MyFlatButton
方法:
- L14 build
- L7 MyFlatButton

## lib/screens/components/recommend_links_panel.dart
类: RecommendLinksPanel, _RecommendLinksPanelState
方法:
- L17 createState
- L22 initState
- L29 dispose
- L35 _setState
- L40 build

## lib/screens/components/right_click_pop.dart
类: (无)
方法:
- L5 rightClickPop

## lib/screens/components/text_preview_screen.dart
类: TextPreviewScreen, _TextPreviewScreenState
方法:
- L13 createState
- L18 build
- L7 TextPreviewScreen

## lib/screens/download_album_screen.dart
类: DownloadAlbumScreen, _DownloadAlbumScreenState
方法:
- L148 _buildContinueButton
- L178 _buildSeries
- L18 DownloadAlbumScreen
- L207 _push
- L21 createState
- L236 _loadChapter
- L29 initState
- L36 build
- L40 buildScreen
- L92 _buildTags

## lib/screens/download_import_screen.dart
类: DownloadImportScreen, _DownloadImportScreenState
方法:
- L153 _importDirFilesZipButton
- L18 DownloadImportScreen
- L21 createState
- L29 initState
- L35 dispose
- L40 _onMessageChange
- L49 build
- L57 buildScreen
- L87 _fileImportButton

## lib/screens/downloads_exporting_screen.dart
类: ExportAb, DownloadsExportingScreen, _DownloadsExportingScreenState
方法:
- L124 _buildButtonInner
- L145 _exportJmis
- L190 _exportPdf
- L229 _exportCbzsZips
- L24 DownloadsExportingScreen
- L274 _exportZips
- L28 createState
- L319 _exportJpegZips
- L364 _exportEpubs
- L40 initState
- L410 build
- L418 buildScreen
- L46 dispose
- L51 _onMessageChange
- L57 _body

## lib/screens/downloads_exporting_screen2.dart
类: ExportAb, DownloadsExportingScreen2, _DownloadsExportingScreen2State
方法:
- L124 _exportJpegs
- L161 _exportPdf2
- L200 _exportEpub
- L238 build
- L24 DownloadsExportingScreen2
- L246 buildScreen
- L28 createState
- L40 initState
- L46 dispose
- L51 _onMessageChange
- L57 _body

## lib/screens/downloads_exports_screen.dart
类: DownloadsExportScreen, _DownloadsExportScreenState
方法:
- L120 _selectAllButton
- L138 _goToExport
- L14 DownloadsExportScreen
- L17 createState
- L24 initState
- L38 build
- L42 buildScreen

## lib/screens/downloads_exports_screen2.dart
类: DownloadsExportScreen2, _DownloadsExportScreen2State
方法:
- L120 _selectAllButton
- L14 DownloadsExportScreen2
- L150 _goToExport
- L17 createState
- L24 initState
- L38 build
- L42 buildScreen

## lib/screens/downloads_screen.dart
类: DownloadsScreen, _DownloadsScreenState
方法:
- L111 importButton
- L128 exportButton
- L145 threadCountButton
- L15 DownloadsScreen
- L18 createState
- L25 _load
- L41 initState
- L47 build
- L51 buildScreen
- L74 _body
- L82 _listView

## lib/screens/favorites_screen.dart
类: FavoritesScreen, _FavoritesScreenState
方法:
- L103 buildScreen
- L11 FavoritesScreen
- L14 createState
- L25 _chooseFolder
- L44 _chooseSort
- L59 initState
- L77 _loadSort
- L99 build

## lib/screens/file_photo_view_screen.dart
类: FilePhotoViewScreen
方法:
- L13 FilePhotoViewScreen
- L16 build
- L20 buildScreen

## lib/screens/first_login_screen.dart
类: FirstLoginScreen, _FirstLoginScreenState
方法:
- L110 build
- L141 _loading
- L145 _form
- L17 FirstLoginScreen
- L20 createState
- L29 _continueAsGuest
- L45 _usernameField
- L65 _passwordField

## lib/screens/init_screen.dart
类: InitScreen, _InitScreenState, AuthScreen, _AuthScreenState
方法:
- L103 initState
- L110 test
- L121 build
- L18 InitScreen
- L21 createState
- L26 initState
- L32 build
- L44 _init
- L95 AuthScreen
- L98 createState

## lib/screens/network_setting_screen.dart
类: NetworkSettingScreen
方法:
- L11 NetworkSettingScreen
- L14 build
- L18 buildScreen

## lib/screens/pro_oh_screen.dart
类: ProOhScreen, _ProScreenState, ProServerNameWidget, _ProServerNameWidgetState
方法:
- L100 initState
- L110 build
- L13 createState
- L133 _loadServerName
- L20 initState
- L30 build
- L34 buildScreen
- L90 ProServerNameWidget
- L93 createState

## lib/screens/pro_screen.dart
类: ProScreen, _ProScreenState, ProServerNameWidget, _ProServerNameWidgetState
方法:
- L11 ProScreen
- L14 createState
- L148 patProWidgets
- L21 initState
- L241 addPatAccount
- L256 reloadPatAccount
- L268 bindThisAccount
- L281 clearPatInfo
- L290 ProServerNameWidget
- L293 createState
- L300 initState
- L310 build
- L32 dispose
- L333 _loadServerName
- L37 _setState
- L42 build
- L46 buildScreen

## lib/screens/settings_screen.dart
类: SettingsScreen, _SettingsState
方法:
- L39 SettingsScreen
- L42 createState
- L49 build
- L53 buildScreen

## lib/screens/user_screen.dart
类: UserScreen, _UserScreenState
方法:
- L112 _buildCard
- L192 _buildLoginButton
- L20 UserScreen
- L220 _buildLoginLoading
- L23 createState
- L232 _buildLoginErrorButton
- L276 _buildSelfInfoCard
- L32 initState
- L40 dispose
- L431 _buildSelfInfoBadge
- L47 _setState
- L475 _formatGender
- L489 _formatExpPercent
- L498 _buildGuestCard
- L511 _buildFavorites
- L52 build
- L527 _buildViewLog
- L540 _buildDownloads
- L553 _buildComments
- L566 _buildSettingsIcon
- L579 _buildAboutIcon

## lib/screens/view_log_screen.dart
类: ViewLogScreen, _ViewLogScreenState
方法:
- L15 ViewLogScreen
- L18 createState
- L26 build
- L30 buildScreen

## lib/screens/week_screen.dart
类: WeekScreen, _WeekScreenState, WeekContent, _WeekContentState
方法:
- L15 createState
- L168 _categorySelectorTextStyle
- L177 _calcCategorySelectorWidth
- L194 _syncAppBarState
- L221 _resolveCategoryId
- L235 _sameCategories
- L26 initState
- L266 createState
- L282 initState
- L298 didUpdateWidget
- L32 dispose
- L322 dispose
- L329 build
- L37 _refresh
- L374 _onPage
- L392 _buildNextCard
- L409 _switchToNextCategory
- L426 _onCategoryChangedFromAppBar
- L441 _resolveInitialCategoryId
- L454 _buildDisplayTypes
- L458 _createTabController
- L469 _needsRebuildTypes
- L47 build
- L88 _buildCategorySelector

