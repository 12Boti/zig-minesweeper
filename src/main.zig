// imports
usingnamespace @cImport({
    @cInclude("glad.h");
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("stb_image.h");
});
const std = @import("std");
const log = std.log;
const gllog = std.log.scoped(.OpenGL);

// constants
const debug = std.builtin.mode == .Debug;
const vertex_shader_spv   = @embedFile("../out/shaders/cells.vert.spv");
const fragment_shader_spv = @embedFile("../out/shaders/cells.frag.spv");
const VertexData = struct {
    pos: [2]f32,
    uv: [2]f32,
};
const vertex_data = [_]VertexData{
    .{.pos = .{ 1, -1}, .uv = .{1, 1}},
    .{.pos = .{-1, -1}, .uv = .{0, 1}},
    .{.pos = .{ 1,  1}, .uv = .{1, 0}},
    .{.pos = .{-1,  1}, .uv = .{0, 0}},
};
const map_size = 10;
const bomb_count = 10;
const cell_size = 1.0 / @as(comptime_float, map_size);
const Cell = packed struct {
    neigh: u4,
    bomb: bool,
    clicked: bool,
    flag: bool,
};

// globals (kinda)
window: *GLFWwindow,
shader_program: GLuint,
vertex_buffer: Buffer(VertexData),
vertex_array: VertexArray(VertexData),
texture: Texture,
rng: std.rand.DefaultPrng,
map: [map_size][map_size]Cell,
window_width: u32,
window_height: u32,

pub fn main() !void {
    var self: @This() = undefined;
    try self.init();
    defer self.cleanup();

    while (glfwWindowShouldClose(self.window) == 0) {
        self.render();
        glfwSwapBuffers(self.window);
        glfwPollEvents();
    }
}

fn render(self: @This()) void {
    glUseProgram(self.shader_program);
    glClearColor(0.5, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glBindVertexArray(self.vertex_array.gl_obj);

    var x: usize = 0;
    while (x < map_size) : (x += 1) {
        var y: usize = 0;
        while (y < map_size) : (y += 1) {
            const cell = self.map[x][y];
            if (cell.clicked) {
                if (cell.bomb) {
                    set_uniform_1(self.shader_program, 3, @as(u32, 11));
                } else {
                    set_uniform_1(self.shader_program, 3, @as(u32, cell.neigh));
                }
            }
            else if (cell.flag) {
                set_uniform_1(self.shader_program, 3, @as(u32, 10));
            }
            else {
                set_uniform_1(self.shader_program, 3, @as(u32, 9));
            }

            set_uniform_2(self.shader_program, 1, @intToFloat(f32, x) - @intToFloat(f32, map_size)/2.0, @intToFloat(f32, y) - @intToFloat(f32, map_size)/2.0);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, vertex_data.len);
        }
    }
}

fn init(self: *@This()) !void {
    { // init rng
        var buf: [8]u8 = undefined;
        try std.crypto.randomBytes(buf[0..]);
        const seed = std.mem.readIntLittle(u64, buf[0..8]);
        self.rng = std.rand.DefaultPrng.init(seed);
    }

    self.init_map();

    if (glfwInit() == 0) return error.glfwInitError;
    errdefer glfwTerminate();

    { // we need to create a window with a context before loading OpenGL
        self.window_width  = 800;
        self.window_height = 800;
        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        if (debug) { glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GLFW_TRUE); } 
        else       { glfwWindowHint(GLFW_CONTEXT_NO_ERROR, GLFW_TRUE);     }
        self.window = glfwCreateWindow(@intCast(c_int, self.window_width), @intCast(c_int, self.window_height), "Minesweeper", null, null) orelse return error.glfwCreateWindowError;
        glfwSetWindowUserPointer(self.window, self);
        glfwMakeContextCurrent(self.window);

        _ = glfwSetFramebufferSizeCallback(self.window, framebuffer_size_callback);
        _ = glfwSetKeyCallback(self.window, key_callback);
        _ = glfwSetMouseButtonCallback(self.window, mouse_button_callback);
        _ = glfwSetWindowSizeCallback(self.window, window_size_callback);
    }

    if (gladLoadGL() == 0) return error.gladLoadGLError;
    log.info("OpenGL {}.{} loaded", .{ GLVersion.major, GLVersion.minor });
    
    if (debug) {
        glEnable(GL_DEBUG_OUTPUT);
        glDebugMessageCallback(debug_callback, self);
    }
    
    self.shader_program = try make_shader_program();
    errdefer glDeleteProgram(self.shader_program);

    self.texture = try load_atlas(12, @embedFile("../assets/cells.png"));
    //glTextureParameteri(self.texture, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    //glTextureParameteri(self.texture, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTextureParameteri(self.texture.gl_obj, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTextureParameteri(self.texture.gl_obj, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glBindTextureUnit(0, self.texture.gl_obj);
    glProgramUniform1i(self.shader_program, 0, 0);

    self.vertex_buffer = Buffer(VertexData).new(&vertex_data);

    self.vertex_array = VertexArray(VertexData).new(self.vertex_buffer);
    
    set_uniform_1(self.shader_program, 2, cell_size);
}

fn cleanup(self: *@This()) void {
    glDeleteProgram(self.shader_program);
    glfwTerminate();
}


fn mouse_button_callback(window: ?*GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    const self = self_from_window(window.?);
    if (action == GLFW_PRESS) {
        var x: f64 = undefined;
        var y: f64 = undefined;
        glfwGetCursorPos(window, &x, &y);
        x = (x/@intToFloat(f64, self.window_width)*2 - 1 + @intToFloat(f64, map_size)*cell_size)/cell_size/2;
        y = ((y/@intToFloat(f64, self.window_height)*2 - 1)*(-1) + @intToFloat(f64, map_size)*cell_size)/cell_size/2;
        log.debug("click: {d} {d}", .{x, y});

        if (x >= 0 and x < map_size and y >= 0 and y < map_size) {
            const cellx = @floatToInt(usize, x);
            const celly = @floatToInt(usize, y);
            log.debug("cell: {} {}", .{cellx, celly});
            
            if (button == GLFW_MOUSE_BUTTON_LEFT and !self.map[cellx][celly].flag) {
                self.map[cellx][celly].clicked = true;
                self.clear_done(cellx, celly);
            }
            else if (button == GLFW_MOUSE_BUTTON_RIGHT and !self.map[cellx][celly].clicked) {
                self.map[cellx][celly].flag = !self.map[cellx][celly].flag;
            }
        }
    }
}

fn clear_done(self: *@This(), x: usize, y: usize) void {
    var found: u32 = 0;
    {
        var a = if (x != 0) x-1 else 0;
        while (a <= (if (x != map_size-1) x+1 else map_size-1)) : (a += 1) {
            var b = if (y != 0) y-1 else 0;
            while (b <= (if (y != map_size-1) y+1 else map_size-1)) : (b += 1) {
                if (self.map[a][b].flag) found += 1;
            }
        }
    }
    if (found == self.map[x][y].neigh) {
        var a = if (x != 0) x-1 else 0;
        while (a <= (if (x != map_size-1) x+1 else map_size-1)) : (a += 1) {
            var b = if (y != 0) y-1 else 0;
            while (b <= (if (y != map_size-1) y+1 else map_size-1)) : (b += 1) {
                if (!self.map[a][b].clicked and !self.map[a][b].flag) {
                    self.map[a][b].clicked = true;
                    self.clear_done(a, b);
                }
            }
        }
    }
}

fn key_callback(window: ?*GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    const self = self_from_window(window.?);
    if (action == GLFW_PRESS) {
        switch (key) {
            GLFW_KEY_ESCAPE => glfwSetWindowShouldClose(self.window, GLFW_TRUE),
            GLFW_KEY_R => self.init_map(),
            else => {}
        }
    }
}

fn init_map(self: *@This()) void {
    for (self.map) |*r| {for (r) |*c| {
        c.clicked = false;
        c.neigh = 0;
        c.flag = false;
    }}

    const r = &self.rng.random;
    var rem_t: usize = bomb_count;
    var idx: usize = 0;
    const s = map_size*map_size;
    while (idx < s) {
        const p = r.uintLessThan(usize, s-idx);
        if (p < rem_t) {
            rem_t -= 1;
            const x = idx / map_size;
            const y = idx % map_size;
            self.map[x][y].bomb = true;

            if (x != 0)          { self.map[x-1][y].neigh += 1; }
            if (x != map_size-1) { self.map[x+1][y].neigh += 1; }
            if (y != 0)          { self.map[x][y-1].neigh += 1; }
            if (y != map_size-1) { self.map[x][y+1].neigh += 1; }
            
            if (x != 0          and y != 0)          { self.map[x-1][y-1].neigh += 1; }
            if (x != map_size-1 and y != 0)          { self.map[x+1][y-1].neigh += 1; }
            if (x != 0          and y != map_size-1) { self.map[x-1][y+1].neigh += 1; }
            if (x != map_size-1 and y != map_size-1) { self.map[x+1][y+1].neigh += 1; }
            
        } else {
            self.map[idx/map_size][idx%map_size].bomb = false;
        }
        idx += 1;
    }
}

fn load_texture(data: []const u8) !Texture {
    var w: c_int = undefined;
    var h: c_int = undefined;
    var channels: c_int = 4;
    const pixels = stbi_load_from_memory(data.ptr, @intCast(c_int, data.len), &w, &h, &channels, channels) orelse return error.stbiLoadError;
    return Texture.new_rgba(@intCast(u32, w), @intCast(u32, h), pixels);
}

fn load_atlas(count: u32, data: []const u8) !Texture {
    var w: c_int = undefined;
    var h: c_int = undefined;
    var channels: c_int = 4;
    const pixels = stbi_load_from_memory(data.ptr, @intCast(c_int, data.len), &w, &h, &channels, channels) orelse return error.stbiLoadError;
    return Texture.new_rgba_atlas(@intCast(u32, w), @divExact(@intCast(u32, h), count), count, pixels);
}

fn Buffer(comptime T: type) type { return struct {
    gl_obj: GLuint,
    size: usize, // in bytes

    pub fn new(data: []const T) @This() {
        var buf: GLuint = undefined;
        glCreateBuffers(1, &buf);
        const size = @sizeOf(T)*data.len;    
        glNamedBufferStorage(buf, @intCast(GLsizeiptr, size), data.ptr, 0);
        return .{.gl_obj = buf, .size = size};
    }
};}

fn VertexArray(comptime T: type) type { return struct {
    gl_obj: GLuint,

    pub fn new(buf: Buffer(T)) @This() {
        var va: GLuint = undefined;
        glCreateVertexArrays(1, &va);
        const fields = @typeInfo(T).Struct.fields;

        comptime var attrib_num = 0;
        inline for (fields) |field| {
            glEnableVertexArrayAttrib(va, attrib_num);
            const format = to_vertex_attrib_format(field.field_type);
            glVertexArrayAttribFormat(va, attrib_num, format.element_count, format.gl_type, GL_FALSE, @byteOffsetOf(T, field.name));

            glVertexArrayAttribBinding(va, attrib_num, 0);

            attrib_num += format.attrib_count;
        }
        glVertexArrayVertexBuffer(va, 0, buf.gl_obj, 0, @sizeOf(T));

        return .{.gl_obj = va};
    }
};}

const Texture = struct {
    gl_obj: GLuint,

    fn new() @This() {
        var gl_obj: GLuint = undefined;
        glCreateTextures(GL_TEXTURE_2D, 1, &gl_obj);
        return .{.gl_obj = gl_obj};
    }

    fn new_rgba(width: u32, height: u32, pixels: [*]const u8) @This() {
        //std.debug.assert(pixels.len == width*height*4);
        var t = @This().new();
        glTextureStorage2D(t.gl_obj, 1, GL_RGBA8, @intCast(c_int, width), @intCast(c_int, height));
        glTextureSubImage2D(t.gl_obj, 0, 0, 0, @intCast(c_int, width), @intCast(c_int, height), GL_RGBA, GL_UNSIGNED_BYTE, pixels);

        return t;
    }

    // needs vertical atlas
    fn new_rgba_atlas(width: u32, height: u32, count: u32, pixels: [*]const u8) @This() {
        var gl_obj: GLuint = undefined;
        glCreateTextures(GL_TEXTURE_2D_ARRAY, 1, &gl_obj);
        glTextureStorage3D(gl_obj, 1, GL_RGBA8, @intCast(c_int, width), @intCast(c_int, height), @intCast(c_int, count));
        glTextureSubImage3D(gl_obj, 0, 0, 0, 0, @intCast(c_int, width), @intCast(c_int, height), @intCast(c_int, count), GL_RGBA, GL_UNSIGNED_BYTE, pixels);
        return .{.gl_obj = gl_obj};
    }
};

fn to_vertex_attrib_format(comptime T: type) VertexAttribFormat {
    const info = @typeInfo(T);
    switch (info) {
        .Array => |a| {
            if (a.len > 4) @compileError("max length of a vec attrib is 4");
            if (a.len < 1) @compileError("min length of a vec attrib is 1");
            return .{.element_count = a.len, .gl_type = to_gl_type(a.child), .attrib_count = 1};
        },
        else => {
            return .{.element_count = 1, .gl_type = to_gl_type(T), .attrib_count = 1};
        }
    }
}

const VertexAttribFormat = struct {
        element_count: comptime_int, 
        gl_type: GLenum,
        attrib_count: comptime_int, // TODO
};

fn to_gl_type(comptime T: type) GLenum {
    return switch (T) {
        i8 => GL_BYTE,
        i16 => GL_SHORT,
        i32 => GL_INT,

        u8 => GL_UNSIGNED_BYTE,
        u16 => GL_UNSIGNED_SHORT,
        u32 => GL_UNSIGNED_INT,

        f16 => GL_HALF_FLOAT,
        f32 => GL_FLOAT,
        f64 => GL_DOUBLE,

        else => @compileError("'" ++ @typeName(T) ++ "' is not a valid OpenGL type")
    };
}

fn set_uniform_1(shader_program: GLuint, location: GLint, value: anytype) void {
    if (@TypeOf(value) == comptime_float) return set_uniform_1(shader_program, location, @as(f32, value));

    glProgramUniform4f(shader_program, location, @bitCast(f32, value), undefined, undefined, undefined);
}

fn set_uniform_2(shader_program: GLuint, location: GLint, value1: anytype, value2: anytype) void {
    if (@TypeOf(value1) == comptime_float) return set_uniform_2(shader_program, location, @as(f32, value1), value2);
    if (@TypeOf(value2) == comptime_float) return set_uniform_2(shader_program, location, value1, @as(f32, value2));

    glProgramUniform4f(shader_program, location, @bitCast(f32, value1), @bitCast(f32, value2), undefined, undefined);
}

fn set_uniform_3(shader_program: GLuint, location: GLint, value1: anytype, value2: anytype, value3: anytype) void {
    if (@TypeOf(value1) == comptime_float) return set_uniform_3(shader_program, location, @as(f32, value1), value2, value3);
    if (@TypeOf(value2) == comptime_float) return set_uniform_3(shader_program, location, value1, @as(f32, value2), value3);
    if (@TypeOf(value3) == comptime_float) return set_uniform_3(shader_program, location, value1, value2, @as(f32, value3));

    glProgramUniform4f(shader_program, location, @bitCast(f32, value1), @bitCast(f32, value2), @bitCast(f32, value3), undefined);
}

fn make_shader_program() !GLuint {
    const new_shader_program = glCreateProgram();

    const vertex_shader = glCreateShader(GL_VERTEX_SHADER);
    defer glDeleteShader(vertex_shader);
    const vs_binary = vertex_shader_spv;
    glShaderBinary(1, &vertex_shader, GL_SHADER_BINARY_FORMAT_SPIR_V, vs_binary, vs_binary.len);
    glSpecializeShader(vertex_shader, "main", 0, 0, 0);
    glAttachShader(new_shader_program, vertex_shader);

    const fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
    defer glDeleteShader(fragment_shader);
    const fs_binary = fragment_shader_spv;
    glShaderBinary(1, &fragment_shader, GL_SHADER_BINARY_FORMAT_SPIR_V, fs_binary, fs_binary.len);
    glSpecializeShader(fragment_shader, "main", 0, 0, 0);
    glAttachShader(new_shader_program, fragment_shader);

    glLinkProgram(new_shader_program);

    var link_success: GLint = undefined;
    glGetProgramiv(new_shader_program, GL_LINK_STATUS, &link_success);
    if (link_success == GL_FALSE) {
        return error.LinkProgramError;
    }

    return new_shader_program;
}

fn window_size_callback(window: ?*GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    const self = self_from_window(window.?);
    self.window_width = @intCast(u32, width);
    self.window_height = @intCast(u32, height);
}

fn framebuffer_size_callback(window: ?*GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    glViewport(0, 0, width, height);
}

fn self_from_window(window: *GLFWwindow) *@This() {
    return @ptrCast(*@This(), @alignCast(@alignOf(@This()), glfwGetWindowUserPointer(window)));
}

fn debug_callback(
    source: GLenum,
    ty: GLenum,
    id: GLuint,
    severity: GLenum,
    length: GLsizei,
    message: [*c]const GLchar,
    userParam: ?*const c_void
) callconv(.C) void {
    const self: *const @This() = @ptrCast(*const @This(), @alignCast(@alignOf(@This()), userParam.?));
    gllog.notice("OpenGL '{}' message: {}", .{gl_debug_type_to_string(ty), message[0..@intCast(usize, length)]});
}

fn gl_debug_type_to_string(ty: GLenum) []const u8 {
    return switch (ty) {
        GL_DEBUG_TYPE_ERROR => "error",
        GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR => "deprecated behavior",
        GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR => "undefined behavior",
        GL_DEBUG_TYPE_PORTABILITY => "portability",
        GL_DEBUG_TYPE_PERFORMANCE => "performance",
        GL_DEBUG_TYPE_OTHER => "other",
        else => "*unknown*",
    };
}