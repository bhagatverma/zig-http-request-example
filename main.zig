const std = @import("std");

pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,

    pub fn toStdMethod(self: HttpMethod) std.http.Method {
        return switch (self) {
            .GET => .GET,
            .POST => .POST,
            .PUT => .PUT,
            .DELETE => .DELETE,
            .PATCH => .PATCH,
            .HEAD => .HEAD,
            .OPTIONS => .OPTIONS,
        };
    }
};

pub const HttpResponse = struct {
    status: std.http.Status,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *HttpResponse) void {
        self.allocator.free(self.body);
    }
};

pub const HttpRequestError = error{
    InvalidUri,
    RequestFailed,
} || std.mem.Allocator.Error || std.http.Client.FetchError;

/// Makes an HTTP request with the specified parameters
/// Caller owns the returned HttpResponse and must call deinit() on it
fn httpRequest(
    allocator: std.mem.Allocator,
    uri: []const u8,
    method: HttpMethod,
    headers: ?[]const std.http.Header,
    payload: ?[]const u8,
) HttpRequestError!HttpResponse {
    const parsed_uri = std.Uri.parse(uri) catch return error.InvalidUri;

    var redirect_buffer: [8 * 1024]u8 = undefined;
    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();
    try body.ensureUnusedCapacity(64);

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const result = try client.fetch(.{
        .location = .{ .uri = parsed_uri },
        .method = method.toStdMethod(),
        .redirect_buffer = &redirect_buffer,
        .response_writer = &body.writer,
        .extra_headers = headers orelse &[_]std.http.Header{},
        .payload = payload,
    });

    return HttpResponse{
        .status = result.status,
        .body = try body.toOwnedSlice(),
        .allocator = allocator,
    };
}

// Example usage
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example 1: GET request
    const headers_get = &[_]std.http.Header{
        .{ .name = "User-Agent", .value = "Zig-Custom-Client/0.15.2" },
        .{ .name = "Accept", .value = "application/json" },
    };

    var response_get = try httpRequest(
        allocator,
        "https://postman-echo.com/get?foo1=bar1&foo2=bar2",
        .GET,
        headers_get,
        null,
    );
    defer response_get.deinit();

    std.debug.print("GET Status: {}\n", .{response_get.status});
    std.debug.print("GET Body: {s}\n\n", .{response_get.body});

    const post_payload =
        \\{
        \\  "foo1": "bar1",
        \\  "foo2": "bar2"
        \\}
    ;
    const payload_length = try std.fmt.allocPrint(allocator, "{}", .{post_payload.len});
    defer allocator.free(payload_length);
    // Example 2: POST request with payload
    const headers_post = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
        // .{ .name = "Content-Length", .value = payload_length },
    };

    var response_post = try httpRequest(
        allocator,
        "https://jsonplaceholder.typicode.com/posts",
        .POST,
        headers_post,
        post_payload,
    );
    defer response_post.deinit();

    std.debug.print("POST Status: {}\n", .{response_post.status});
    std.debug.print("POST Body: {s}\n\n", .{response_post.body});

    // Example 3: PUT request
    const put_payload =
        \\{
        \\  "id": 1,
        \\  "title": "updated title",
        \\  "body": "updated body",
        \\  "userId": 1
        \\}
    ;

    var response_put = try httpRequest(
        allocator,
        "https://postman-echo.com/posts/1",
        .PUT,
        headers_post,
        put_payload,
    );
    defer response_put.deinit();

    std.debug.print("PUT Status: {}\n", .{response_put.status});
    std.debug.print("PUT Body: {s}\n\n", .{response_put.body});

    // Example 4: DELETE request
    var response_delete = try httpRequest(
        allocator,
        "https://postman-echo.com/delete",
        .DELETE,
        headers_post,
        null,
    );
    defer response_delete.deinit();

    std.debug.print("DELETE Status: {}\n", .{response_delete.status});
    std.debug.print("DELETE Body: {s}\n", .{response_delete.body});
}
