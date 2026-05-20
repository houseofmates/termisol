enum TerminalKey {
  /// represents the logical "none" key on the keyboard.
  none,

  /// represents the logical "hyper" key on the keyboard.
  hyper,

  /// represents the logical "super key" key on the keyboard.
  superKey,

  /// represents the logical "fn lock" key on the keyboard.
  fnLock,

  /// represents the logical "suspend" key on the keyboard.
  suspend,

  /// represents the logical "resume" key on the keyboard.
  resume,

  /// represents the logical "turbo" key on the keyboard.
  turbo,

  /// represents the logical "privacy screen toggle" key on the keyboard.
  privacyScreenToggle,

  /// represents the logical "sleep" key on the keyboard.
  sleep,

  /// represents the logical "wake up" key on the keyboard.
  wakeUp,

  /// represents the logical "display toggle int ext" key on the keyboard.
  displayToggleIntExt,

  /// represents the logical "usb reserved" key on the keyboard.
  usbReserved,

  /// represents the logical "usb error roll over" key on the keyboard.
  usbErrorRollOver,

  /// represents the logical "usb post fail" key on the keyboard.
  usbPostFail,

  /// represents the logical "usb error undefined" key on the keyboard.
  usbErrorUndefined,

  /// represents the logical "key a" key on the keyboard.
  keyA,

  /// represents the logical "key b" key on the keyboard.
  keyB,

  /// represents the logical "key c" key on the keyboard.
  keyC,

  /// represents the logical "key d" key on the keyboard.
  keyD,

  /// represents the logical "key e" key on the keyboard.
  keyE,

  /// represents the logical "key f" key on the keyboard.
  keyF,

  /// represents the logical "key g" key on the keyboard.
  keyG,

  /// represents the logical "key h" key on the keyboard.
  keyH,

  /// represents the logical "key i" key on the keyboard.
  keyI,

  /// represents the logical "key j" key on the keyboard.
  keyJ,

  /// represents the logical "key k" key on the keyboard.
  keyK,

  /// represents the logical "key l" key on the keyboard.
  keyL,

  /// represents the logical "key m" key on the keyboard.
  keyM,

  /// represents the logical "key n" key on the keyboard.
  keyN,

  /// represents the logical "key o" key on the keyboard.
  keyO,

  /// represents the logical "key p" key on the keyboard.
  keyP,

  /// represents the logical "key q" key on the keyboard.
  keyQ,

  /// represents the logical "key r" key on the keyboard.
  keyR,

  /// represents the logical "key s" key on the keyboard.
  keyS,

  /// represents the logical "key t" key on the keyboard.
  keyT,

  /// represents the logical "key u" key on the keyboard.
  keyU,

  /// represents the logical "key v" key on the keyboard.
  keyV,

  /// represents the logical "key w" key on the keyboard.
  keyW,

  /// represents the logical "key x" key on the keyboard.
  keyX,

  /// represents the logical "key y" key on the keyboard.
  keyY,

  /// represents the logical "key z" key on the keyboard.
  keyZ,

  /// represents the logical "digit 1" key on the keyboard.
  digit1,

  /// represents the logical "digit 2" key on the keyboard.
  digit2,

  /// represents the logical "digit 3" key on the keyboard.
  digit3,

  /// represents the logical "digit 4" key on the keyboard.
  digit4,

  /// represents the logical "digit 5" key on the keyboard.
  digit5,

  /// represents the logical "digit 6" key on the keyboard.
  digit6,

  /// represents the logical "digit 7" key on the keyboard.
  digit7,

  /// represents the logical "digit 8" key on the keyboard.
  digit8,

  /// represents the logical "digit 9" key on the keyboard.
  digit9,

  /// represents the logical "digit 0" key on the keyboard.
  digit0,

  /// represents the logical "enter" key on the keyboard.
  enter,

  /// represents the logical "escape" key on the keyboard.
  escape,

  /// represents the logical "backspace" key on the keyboard.
  backspace,

  /// represents the logical "tab" key on the keyboard.
  tab,

  /// represents the logical "space" key on the keyboard.
  space,

  /// represents the logical "minus" key on the keyboard.
  minus,

  /// represents the logical "equal" key on the keyboard.
  equal,

  /// represents the logical "bracket left" key on the keyboard.
  bracketLeft,

  /// represents the logical "bracket right" key on the keyboard.
  bracketRight,

  /// represents the logical "backslash" key on the keyboard.
  backslash,

  /// represents the logical "semicolon" key on the keyboard.
  semicolon,

  /// represents the logical "quote" key on the keyboard.
  quote,

  /// represents the logical "backquote" key on the keyboard.
  backquote,

  /// represents the logical "comma" key on the keyboard.
  comma,

  /// represents the logical "period" key on the keyboard.
  period,

  /// represents the logical "slash" key on the keyboard.
  slash,

  /// represents the logical "caps lock" key on the keyboard.
  capsLock,

  /// represents the logical "f1" key on the keyboard.
  f1,

  /// represents the logical "f2" key on the keyboard.
  f2,

  /// represents the logical "f3" key on the keyboard.
  f3,

  /// represents the logical "f4" key on the keyboard.
  f4,

  /// represents the logical "f5" key on the keyboard.
  f5,

  /// represents the logical "f6" key on the keyboard.
  f6,

  /// represents the logical "f7" key on the keyboard.
  f7,

  /// represents the logical "f8" key on the keyboard.
  f8,

  /// represents the logical "f9" key on the keyboard.
  f9,

  /// represents the logical "f10" key on the keyboard.
  f10,

  /// represents the logical "f11" key on the keyboard.
  f11,

  /// represents the logical "f12" key on the keyboard.
  f12,

  /// represents the logical "print screen" key on the keyboard.
  printScreen,

  /// represents the logical "scroll lock" key on the keyboard.
  scrollLock,

  /// represents the logical "pause" key on the keyboard.
  pause,

  /// represents the logical "insert" key on the keyboard.
  insert,

  /// represents the logical "home" key on the keyboard.
  home,

  /// represents the logical "page up" key on the keyboard.
  pageUp,

  /// represents the logical "delete" key on the keyboard.
  delete,

  /// represents the logical "end" key on the keyboard.
  end,

  /// represents the logical "page down" key on the keyboard.
  pageDown,

  /// represents the logical "arrow right" key on the keyboard.
  arrowRight,

  /// represents the logical "arrow left" key on the keyboard.
  arrowLeft,

  /// represents the logical "arrow down" key on the keyboard.
  arrowDown,

  /// represents the logical "arrow up" key on the keyboard.
  arrowUp,

  /// represents the logical "num lock" key on the keyboard.
  numLock,

  /// represents the logical "numpad divide" key on the keyboard.
  numpadDivide,

  /// represents the logical "numpad multiply" key on the keyboard.
  numpadMultiply,

  /// represents the logical "numpad subtract" key on the keyboard.
  numpadSubtract,

  /// represents the logical "numpad add" key on the keyboard.
  numpadAdd,

  /// represents the logical "numpad enter" key on the keyboard.
  numpadEnter,

  /// represents the logical "numpad 1" key on the keyboard.
  numpad1,

  /// represents the logical "numpad 2" key on the keyboard.
  numpad2,

  /// represents the logical "numpad 3" key on the keyboard.
  numpad3,

  /// represents the logical "numpad 4" key on the keyboard.
  numpad4,

  /// represents the logical "numpad 5" key on the keyboard.
  numpad5,

  /// represents the logical "numpad 6" key on the keyboard.
  numpad6,

  /// represents the logical "numpad 7" key on the keyboard.
  numpad7,

  /// represents the logical "numpad 8" key on the keyboard.
  numpad8,

  /// represents the logical "numpad 9" key on the keyboard.
  numpad9,

  /// represents the logical "numpad 0" key on the keyboard.
  numpad0,

  /// represents the logical "numpad decimal" key on the keyboard.
  numpadDecimal,

  /// represents the logical "intl backslash" key on the keyboard.
  intlBackslash,

  /// represents the logical "context menu" key on the keyboard.
  contextMenu,

  /// represents the logical "power" key on the keyboard.
  power,

  /// represents the logical "numpad equal" key on the keyboard.
  numpadEqual,

  /// represents the logical "f13" key on the keyboard.
  f13,

  /// represents the logical "f14" key on the keyboard.
  f14,

  /// represents the logical "f15" key on the keyboard.
  f15,

  /// represents the logical "f16" key on the keyboard.
  f16,

  /// represents the logical "f17" key on the keyboard.
  f17,

  /// represents the logical "f18" key on the keyboard.
  f18,

  /// represents the logical "f19" key on the keyboard.
  f19,

  /// represents the logical "f20" key on the keyboard.
  f20,

  /// represents the logical "f21" key on the keyboard.
  f21,

  /// represents the logical "f22" key on the keyboard.
  f22,

  /// represents the logical "f23" key on the keyboard.
  f23,

  /// represents the logical "f24" key on the keyboard.
  f24,

  /// represents the logical "open" key on the keyboard.
  open,

  /// represents the logical "help" key on the keyboard.
  help,

  /// represents the logical "select" key on the keyboard.
  select,

  /// represents the logical "again" key on the keyboard.
  again,

  /// represents the logical "undo" key on the keyboard.
  undo,

  /// represents the logical "cut" key on the keyboard.
  cut,

  /// represents the logical "copy" key on the keyboard.
  copy,

  /// represents the logical "paste" key on the keyboard.
  paste,

  /// represents the logical "find" key on the keyboard.
  find,

  /// represents the logical "audio volume mute" key on the keyboard.
  audioVolumeMute,

  /// represents the logical "audio volume up" key on the keyboard.
  audioVolumeUp,

  /// represents the logical "audio volume down" key on the keyboard.
  audioVolumeDown,

  /// represents the logical "numpad comma" key on the keyboard.
  numpadComma,

  /// represents the logical "intl ro" key on the keyboard.
  intlRo,

  /// represents the logical "kana mode" key on the keyboard.
  kanaMode,

  /// represents the logical "intl yen" key on the keyboard.
  intlYen,

  /// represents the logical "convert" key on the keyboard.
  convert,

  /// represents the logical "non convert" key on the keyboard.
  nonConvert,

  /// represents the logical "lang 1" key on the keyboard.
  lang1,

  /// represents the logical "lang 2" key on the keyboard.
  lang2,

  /// represents the logical "lang 3" key on the keyboard.
  lang3,

  /// represents the logical "lang 4" key on the keyboard.
  lang4,

  /// represents the logical "lang 5" key on the keyboard.
  lang5,

  /// represents the logical "abort" key on the keyboard.
  abort,

  /// represents the logical "props" key on the keyboard.
  props,

  /// represents the logical "numpad paren left" key on the keyboard.
  numpadParenLeft,

  /// represents the logical "numpad paren right" key on the keyboard.
  numpadParenRight,

  /// represents the logical "numpad backspace" key on the keyboard.
  numpadBackspace,

  /// represents the logical "numpad memory store" key on the keyboard.
  numpadMemoryStore,

  /// represents the logical "numpad memory recall" key on the keyboard.
  numpadMemoryRecall,

  /// represents the logical "numpad memory clear" key on the keyboard.
  numpadMemoryClear,

  /// represents the logical "numpad memory add" key on the keyboard.
  numpadMemoryAdd,

  /// represents the logical "numpad memory subtract" key on the keyboard.
  numpadMemorySubtract,

  /// represents the logical "numpad sign change" key on the keyboard.
  numpadSignChange,

  /// represents the logical "numpad clear" key on the keyboard.
  numpadClear,

  /// represents the logical "numpad clear entry" key on the keyboard.
  numpadClearEntry,

  /// represents the logical "control left" key on the keyboard.
  controlLeft,

  /// represents the logical "shift left" key on the keyboard.
  shiftLeft,

  /// represents the logical "alt left" key on the keyboard.
  altLeft,

  /// represents the logical "meta left" key on the keyboard.
  metaLeft,

  /// represents the logical "control right" key on the keyboard.
  controlRight,

  /// represents the logical "shift right" key on the keyboard.
  shiftRight,

  /// represents the logical "alt right" key on the keyboard.
  altRight,

  /// represents the logical "meta right" key on the keyboard.
  metaRight,

  /// represents the logical "info" key on the keyboard.
  info,

  /// represents the logical "closed caption toggle" key on the keyboard.
  closedCaptionToggle,

  /// represents the logical "brightness up" key on the keyboard.
  brightnessUp,

  /// represents the logical "brightness down" key on the keyboard.
  brightnessDown,

  /// represents the logical "brightness toggle" key on the keyboard.
  brightnessToggle,

  /// represents the logical "brightness minimum" key on the keyboard.
  brightnessMinimum,

  /// represents the logical "brightness maximum" key on the keyboard.
  brightnessMaximum,

  /// represents the logical "brightness auto" key on the keyboard.
  brightnessAuto,

  /// represents the logical "media last" key on the keyboard.
  mediaLast,

  /// represents the logical "launch phone" key on the keyboard.
  launchPhone,

  /// represents the logical "program guide" key on the keyboard.
  programGuide,

  /// represents the logical "exit" key on the keyboard.
  exit,

  /// represents the logical "channel up" key on the keyboard.
  channelUp,

  /// represents the logical "channel down" key on the keyboard.
  channelDown,

  /// represents the logical "media play" key on the keyboard.
  mediaPlay,

  /// represents the logical "media pause" key on the keyboard.
  mediaPause,

  /// represents the logical "media record" key on the keyboard.
  mediaRecord,

  /// represents the logical "media fast forward" key on the keyboard.
  mediaFastForward,

  /// represents the logical "media rewind" key on the keyboard.
  mediaRewind,

  /// represents the logical "media track next" key on the keyboard.
  mediaTrackNext,

  /// represents the logical "media track previous" key on the keyboard.
  mediaTrackPrevious,

  /// represents the logical "media stop" key on the keyboard.
  mediaStop,

  /// represents the logical "eject" key on the keyboard.
  eject,

  /// represents the logical "media play pause" key on the keyboard.
  mediaPlayPause,

  /// represents the logical "speech input toggle" key on the keyboard.
  speechInputToggle,

  /// represents the logical "bass boost" key on the keyboard.
  bassBoost,

  /// represents the logical "media select" key on the keyboard.
  mediaSelect,

  /// represents the logical "launch word processor" key on the keyboard.
  launchWordProcessor,

  /// represents the logical "launch spreadsheet" key on the keyboard.
  launchSpreadsheet,

  /// represents the logical "launch mail" key on the keyboard.
  launchMail,

  /// represents the logical "launch contacts" key on the keyboard.
  launchContacts,

  /// represents the logical "launch calendar" key on the keyboard.
  launchCalendar,

  /// represents the logical "launch app2" key on the keyboard.
  launchApp2,

  /// represents the logical "launch app1" key on the keyboard.
  launchApp1,

  /// represents the logical "launch internet browser" key on the keyboard.
  launchInternetBrowser,

  /// represents the logical "log off" key on the keyboard.
  logOff,

  /// represents the logical "lock screen" key on the keyboard.
  lockScreen,

  /// represents the logical "launch control panel" key on the keyboard.
  launchControlPanel,

  /// represents the logical "select task" key on the keyboard.
  selectTask,

  /// represents the logical "launch documents" key on the keyboard.
  launchDocuments,

  /// represents the logical "spell check" key on the keyboard.
  spellCheck,

  /// represents the logical "launch keyboard layout" key on the keyboard.
  launchKeyboardLayout,

  /// represents the logical "launch screen saver" key on the keyboard.
  launchScreenSaver,

  /// represents the logical "launch assistant" key on the keyboard.
  launchAssistant,

  /// represents the logical "launch audio browser" key on the keyboard.
  launchAudioBrowser,

  /// represents the logical "new key" key on the keyboard.
  newKey,

  /// represents the logical "close" key on the keyboard.
  close,

  /// represents the logical "save" key on the keyboard.
  save,

  /// represents the logical "print" key on the keyboard.
  print,

  /// represents the logical "browser search" key on the keyboard.
  browserSearch,

  /// represents the logical "browser home" key on the keyboard.
  browserHome,

  /// represents the logical "browser back" key on the keyboard.
  browserBack,

  /// represents the logical "browser forward" key on the keyboard.
  browserForward,

  /// represents the logical "browser stop" key on the keyboard.
  browserStop,

  /// represents the logical "browser refresh" key on the keyboard.
  browserRefresh,

  /// represents the logical "browser favorites" key on the keyboard.
  browserFavorites,

  /// represents the logical "zoom in" key on the keyboard.
  zoomIn,

  /// represents the logical "zoom out" key on the keyboard.
  zoomOut,

  /// represents the logical "zoom toggle" key on the keyboard.
  zoomToggle,

  /// represents the logical "redo" key on the keyboard.
  redo,

  /// represents the logical "mail reply" key on the keyboard.
  mailReply,

  /// represents the logical "mail forward" key on the keyboard.
  mailForward,

  /// represents the logical "mail send" key on the keyboard.
  mailSend,

  /// represents the logical "keyboard layout select" key on the keyboard.
  keyboardLayoutSelect,

  /// represents the logical "show all windows" key on the keyboard.
  showAllWindows,

  /// represents the logical "game button 1" key on the keyboard.
  gameButton1,

  /// represents the logical "game button 2" key on the keyboard.
  gameButton2,

  /// represents the logical "game button 3" key on the keyboard.
  gameButton3,

  /// represents the logical "game button 4" key on the keyboard.
  gameButton4,

  /// represents the logical "game button 5" key on the keyboard.
  gameButton5,

  /// represents the logical "game button 6" key on the keyboard.
  gameButton6,

  /// represents the logical "game button 7" key on the keyboard.
  gameButton7,

  /// represents the logical "game button 8" key on the keyboard.
  gameButton8,

  /// represents the logical "game button 9" key on the keyboard.
  gameButton9,

  /// represents the logical "game button 10" key on the keyboard.
  gameButton10,

  /// represents the logical "game button 11" key on the keyboard.
  gameButton11,

  /// represents the logical "game button 12" key on the keyboard.
  gameButton12,

  /// represents the logical "game button 13" key on the keyboard.
  gameButton13,

  /// represents the logical "game button 14" key on the keyboard.
  gameButton14,

  /// represents the logical "game button 15" key on the keyboard.
  gameButton15,

  /// represents the logical "game button 16" key on the keyboard.
  gameButton16,

  /// represents the logical "game button a" key on the keyboard.
  gameButtonA,

  /// represents the logical "game button b" key on the keyboard.
  gameButtonB,

  /// represents the logical "game button c" key on the keyboard.
  gameButtonC,

  /// represents the logical "game button left 1" key on the keyboard.
  gameButtonLeft1,

  /// represents the logical "game button left 2" key on the keyboard.
  gameButtonLeft2,

  /// represents the logical "game button mode" key on the keyboard.
  gameButtonMode,

  /// represents the logical "game button right 1" key on the keyboard.
  gameButtonRight1,

  /// represents the logical "game button right 2" key on the keyboard.
  gameButtonRight2,

  /// represents the logical "game button select" key on the keyboard.
  gameButtonSelect,

  /// represents the logical "game button start" key on the keyboard.
  gameButtonStart,

  /// represents the logical "game button thumb left" key on the keyboard.
  gameButtonThumbLeft,

  /// represents the logical "game button thumb right" key on the keyboard.
  gameButtonThumbRight,

  /// represents the logical "game button x" key on the keyboard.
  gameButtonX,

  /// represents the logical "game button y" key on the keyboard.
  gameButtonY,

  /// represents the logical "game button z" key on the keyboard.
  gameButtonZ,

  /// represents the logical "fn" key on the keyboard.
  fn,

  /// represents the logical "shift" key on the keyboard.
  ///
  /// this key represents the union of the keys {shiftleft, shiftright} when
  /// comparing keys. this key will never be generated directly, its main use is
  /// in defining key maps.
  shift,

  /// represents the logical "meta" key on the keyboard.
  ///
  /// this key represents the union of the keys {metaleft, metaright} when
  /// comparing keys. this key will never be generated directly, its main use is
  /// in defining key maps.
  meta,

  /// represents the logical "alt" key on the keyboard.
  ///
  /// this key represents the union of the keys {altleft, altright} when
  /// comparing keys. this key will never be generated directly, its main use is
  /// in defining key maps.
  alt,

  /// represents the logical "control" key on the keyboard.
  ///
  /// this key represents the union of the keys {controlleft, controlright} when
  /// comparing keys. this key will never be generated directly, its main use is
  /// in defining key maps.
  control,

  // missing flutter keys.

  backtab,
  returnKey,
}
