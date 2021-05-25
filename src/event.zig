const Vec2i = @import("math").Vec2i;

pub const EventTag = enum {
    Quit,

    ScreenResized,

    KeyDown,
    KeyUp,
    TextEditing,
    TextInput,

    MouseMotion,
    MouseButtonDown,
    MouseButtonUp,
    MouseWheel,

    ControllerAxis,
    ControllerButtonDown,
    ControllerButtonUp,

    Custom,
};

pub const Event = union(enum) {
    Quit: void,

    ScreenResized: Vec2i,

    KeyDown: KeyEvent,
    KeyUp: KeyEvent,
    TextEditing: void,
    TextInput: TextInput,

    MouseMotion: MouseMoveEvent,
    MouseButtonDown: MouseButtonEvent,
    MouseButtonUp: MouseButtonEvent,
    MouseWheel: Vec2i,

    ControllerAxis: ControllerAxisEvent,
    ControllerButtonDown: ControllerButtonEvent,
    ControllerButtonUp: ControllerButtonEvent,

    Custom: u32,
};

pub const KeyEvent = struct {
    key: Keycode,
    scancode: Scancode,
};

pub const TextInput = struct {
    // The backing buffer for text
    buf: [32]u8,
    len: usize,

    pub fn text(this: *const @This()) []const u8 {
        return this.buf[0..this.len];
    }
};

pub const MouseButton = enum(u8) {
    Left,
    Middle,
    Right,
    X1,
    X2,

    pub fn to_buttons_number(self: @This()) u32 {
        return switch (self) {
            .Left => MOUSE_BUTTONS.PRIMARY,
            .Middle => MOUSE_BUTTONS.AUXILIARY,
            .Right => MOUSE_BUTTONS.SECONDARY,
            .X1 => MOUSE_BUTTONS.X1,
            .X2 => MOUSE_BUTTONS.X2,
        };
    }
};

pub const MOUSE_BUTTONS = struct {
    pub const PRIMARY = 0x01;
    pub const SECONDARY = 0x02;
    pub const AUXILIARY = 0x04;
    pub const X1 = 0x08;
    pub const X2 = 0x10;
};

pub const MouseMoveEvent = struct {
    pos: Vec2i,
    rel: Vec2i,
    buttons: u32,

    pub fn is_pressed(self: @This(), button: MouseButton) bool {
        const flag = button.to_buttons_number();
        return self.buttons & flag == flag;
    }
};

pub const MouseButtonEvent = struct { pos: Vec2i, button: MouseButton };

// Controller

pub const ControllerAxisEvent = struct {
    timestamp: u32,
    joystickID: i32,
    axis: ControllerAxis,
    value: i16,
};

pub const ControllerAxis = enum(u8) {
    INVALID = @bitCast(u8, @as(i8, -1)),
    LEFTX = 0,
    LEFTY,
    RIGHTX,
    RIGHTY,
    TRIGGERLEFT,
    TRIGGERRIGHT,
    MAX,
};

pub const ControllerButtonEvent = struct {
    timestamp: u32,
    joystickID: i32,
    button: ControllerButton,
    pressed: bool,
};

pub const ControllerButton = enum(u8) {
    INVALID = @bitCast(u8, @as(i8, -1)),
    A = 0,
    B,
    X,
    Y,
    BACK,
    GUIDE,
    START,
    LEFTSTICK,
    RIGHTSTICK,
    LEFTSHOULDER,
    RIGHTSHOULDER,
    DPAD_UP,
    DPAD_DOWN,
    DPAD_LEFT,
    DPAD_RIGHT,
    MISC1,
    PADDLE1,
    PADDLE2,
    PADDLE3,
    PADDLE4,
    TOUCHPAD,
    MAX,
};

pub const Scancode = enum(u16) {
    UNKNOWN,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    _1,
    _2,
    _3,
    _4,
    _5,
    _6,
    _7,
    _8,
    _9,
    _0,
    RETURN,
    ESCAPE,
    BACKSPACE,
    TAB,
    SPACE,
    MINUS,
    EQUALS,
    LEFTBRACKET,
    RIGHTBRACKET,
    BACKSLASH,
    NONUSHASH,
    SEMICOLON,
    APOSTROPHE,
    GRAVE,
    COMMA,
    PERIOD,
    SLASH,
    CAPSLOCK,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    PRINTSCREEN,
    SCROLLLOCK,
    PAUSE,
    INSERT,
    HOME,
    PAGEUP,
    DELETE,
    END,
    PAGEDOWN,
    RIGHT,
    LEFT,
    DOWN,
    UP,
    NUMLOCKCLEAR,
    KP_DIVIDE,
    KP_MULTIPLY,
    KP_MINUS,
    KP_PLUS,
    KP_ENTER,
    KP_1,
    KP_2,
    KP_3,
    KP_4,
    KP_5,
    KP_6,
    KP_7,
    KP_8,
    KP_9,
    KP_0,
    KP_PERIOD,
    NONUSBACKSLASH,
    APPLICATION,
    POWER,
    KP_EQUALS,
    F13,
    F14,
    F15,
    F16,
    F17,
    F18,
    F19,
    F20,
    F21,
    F22,
    F23,
    F24,
    EXECUTE,
    HELP,
    MENU,
    SELECT,
    STOP,
    AGAIN,
    UNDO,
    CUT,
    COPY,
    PASTE,
    FIND,
    MUTE,
    VOLUMEUP,
    VOLUMEDOWN,
    KP_COMMA,
    KP_EQUALSAS400,
    INTERNATIONAL1,
    INTERNATIONAL2,
    INTERNATIONAL3,
    INTERNATIONAL4,
    INTERNATIONAL5,
    INTERNATIONAL6,
    INTERNATIONAL7,
    INTERNATIONAL8,
    INTERNATIONAL9,
    LANG1,
    LANG2,
    LANG3,
    LANG4,
    LANG5,
    LANG6,
    LANG7,
    LANG8,
    LANG9,
    ALTERASE,
    SYSREQ,
    CANCEL,
    CLEAR,
    PRIOR,
    RETURN2,
    SEPARATOR,
    OUT,
    OPER,
    CLEARAGAIN,
    CRSEL,
    EXSEL,
    KP_00,
    KP_000,
    THOUSANDSSEPARATOR,
    DECIMALSEPARATOR,
    CURRENCYUNIT,
    CURRENCYSUBUNIT,
    KP_LEFTPAREN,
    KP_RIGHTPAREN,
    KP_LEFTBRACE,
    KP_RIGHTBRACE,
    KP_TAB,
    KP_BACKSPACE,
    KP_A,
    KP_B,
    KP_C,
    KP_D,
    KP_E,
    KP_F,
    KP_XOR,
    KP_POWER,
    KP_PERCENT,
    KP_LESS,
    KP_GREATER,
    KP_AMPERSAND,
    KP_DBLAMPERSAND,
    KP_VERTICALBAR,
    KP_DBLVERTICALBAR,
    KP_COLON,
    KP_HASH,
    KP_SPACE,
    KP_AT,
    KP_EXCLAM,
    KP_MEMSTORE,
    KP_MEMRECALL,
    KP_MEMCLEAR,
    KP_MEMADD,
    KP_MEMSUBTRACT,
    KP_MEMMULTIPLY,
    KP_MEMDIVIDE,
    KP_PLUSMINUS,
    KP_CLEAR,
    KP_CLEARENTRY,
    KP_BINARY,
    KP_OCTAL,
    KP_DECIMAL,
    KP_HEXADECIMAL,
    LCTRL,
    LSHIFT,
    LALT,
    LGUI,
    RCTRL,
    RSHIFT,
    RALT,
    RGUI,
    MODE,
    AUDIONEXT,
    AUDIOPREV,
    AUDIOSTOP,
    AUDIOPLAY,
    AUDIOMUTE,
    MEDIASELECT,
    WWW,
    MAIL,
    CALCULATOR,
    COMPUTER,
    AC_SEARCH,
    AC_HOME,
    AC_BACK,
    AC_FORWARD,
    AC_STOP,
    AC_REFRESH,
    AC_BOOKMARKS,
    BRIGHTNESSDOWN,
    BRIGHTNESSUP,
    DISPLAYSWITCH,
    KBDILLUMTOGGLE,
    KBDILLUMDOWN,
    KBDILLUMUP,
    EJECT,
    SLEEP,
    APP1,
    APP2,
};

pub const CursorStyle = enum {
    default,
    move,
    grabbing,
};

pub const Keycode = enum(u16) {
    _0,
    _1,
    _2,
    _3,
    _4,
    _5,
    _6,
    _7,
    _8,
    _9,
    a,
    AC_BACK,
    AC_BOOKMARKS,
    AC_FORWARD,
    AC_HOME,
    AC_REFRESH,
    AC_SEARCH,
    AC_STOP,
    AGAIN,
    ALTERASE,
    QUOTE,
    APPLICATION,
    AUDIOMUTE,
    AUDIONEXT,
    AUDIOPLAY,
    AUDIOPREV,
    AUDIOSTOP,
    b,
    BACKSLASH,
    BACKSPACE,
    BRIGHTNESSDOWN,
    BRIGHTNESSUP,
    c,
    CALCULATOR,
    CANCEL,
    CAPSLOCK,
    CLEAR,
    CLEARAGAIN,
    COMMA,
    COMPUTER,
    COPY,
    CRSEL,
    CURRENCYSUBUNIT,
    CURRENCYUNIT,
    CUT,
    d,
    DECIMALSEPARATOR,
    DELETE,
    DISPLAYSWITCH,
    DOWN,
    e,
    EJECT,
    END,
    EQUALS,
    ESCAPE,
    EXECUTE,
    EXSEL,
    f,
    F1,
    F10,
    F11,
    F12,
    F13,
    F14,
    F15,
    F16,
    F17,
    F18,
    F19,
    F2,
    F20,
    F21,
    F22,
    F23,
    F24,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    FIND,
    g,
    BACKQUOTE,
    h,
    HELP,
    HOME,
    i,
    INSERT,
    j,
    k,
    KBDILLUMDOWN,
    KBDILLUMTOGGLE,
    KBDILLUMUP,
    KP_0,
    KP_00,
    KP_000,
    KP_1,
    KP_2,
    KP_3,
    KP_4,
    KP_5,
    KP_6,
    KP_7,
    KP_8,
    KP_9,
    KP_A,
    KP_AMPERSAND,
    KP_AT,
    KP_B,
    KP_BACKSPACE,
    KP_BINARY,
    KP_C,
    KP_CLEAR,
    KP_CLEARENTRY,
    KP_COLON,
    KP_COMMA,
    KP_D,
    KP_DBLAMPERSAND,
    KP_DBLVERTICALBAR,
    KP_DECIMAL,
    KP_DIVIDE,
    KP_E,
    KP_ENTER,
    KP_EQUALS,
    KP_EQUALSAS400,
    KP_EXCLAM,
    KP_F,
    KP_GREATER,
    KP_HASH,
    KP_HEXADECIMAL,
    KP_LEFTBRACE,
    KP_LEFTPAREN,
    KP_LESS,
    KP_MEMADD,
    KP_MEMCLEAR,
    KP_MEMDIVIDE,
    KP_MEMMULTIPLY,
    KP_MEMRECALL,
    KP_MEMSTORE,
    KP_MEMSUBTRACT,
    KP_MINUS,
    KP_MULTIPLY,
    KP_OCTAL,
    KP_PERCENT,
    KP_PERIOD,
    KP_PLUS,
    KP_PLUSMINUS,
    KP_POWER,
    KP_RIGHTBRACE,
    KP_RIGHTPAREN,
    KP_SPACE,
    KP_TAB,
    KP_VERTICALBAR,
    KP_XOR,
    l,
    LALT,
    LCTRL,
    LEFT,
    LEFTBRACKET,
    LGUI,
    LSHIFT,
    m,
    MAIL,
    MEDIASELECT,
    MENU,
    MINUS,
    MODE,
    MUTE,
    n,
    NUMLOCKCLEAR,
    o,
    OPER,
    OUT,
    p,
    PAGEDOWN,
    PAGEUP,
    PASTE,
    PAUSE,
    PERIOD,
    POWER,
    PRINTSCREEN,
    PRIOR,
    q,
    r,
    RALT,
    RCTRL,
    RETURN,
    RETURN2,
    RGUI,
    RIGHT,
    RIGHTBRACKET,
    RSHIFT,
    s,
    SCROLLLOCK,
    SELECT,
    SEMICOLON,
    SEPARATOR,
    SLASH,
    SLEEP,
    SPACE,
    STOP,
    SYSREQ,
    t,
    TAB,
    THOUSANDSSEPARATOR,
    u,
    UNDO,
    UNKNOWN,
    UP,
    v,
    VOLUMEDOWN,
    VOLUMEUP,
    w,
    WWW,
    x,
    y,
    z,
    AMPERSAND,
    ASTERISK,
    AT,
    CARET,
    COLON,
    DOLLAR,
    EXCLAIM,
    GREATER,
    HASH,
    LEFTPAREN,
    LESS,
    PERCENT,
    PLUS,
    QUESTION,
    QUOTEDBL,
    RIGHTPAREN,
    UNDERSCORE,
};
