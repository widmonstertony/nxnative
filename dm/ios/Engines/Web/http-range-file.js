/* TonTon read-only local HTTP file adapter. MIT; game data stays on disk. */
(function (scope) {
    'use strict';
    function attach(FS, path, url, size, options) {
        options = options || {};
        const block = options.blockBytes || 1048576;
        const limit = options.cacheBlocks || 3;
        if (!Number.isSafeInteger(size) || size <= 0 ||
            !Number.isSafeInteger(block) || block < 1 || block > 8388608 ||
            !Number.isSafeInteger(limit) || limit < 1 || limit > 8) {
            throw new Error('Invalid bounded HTTP file configuration');
        }
        const cache = new Map();
        function fail(message) {
            console.error('TonTon range file: ' + message);
            if (FS.ErrnoError) throw new FS.ErrnoError(29); // Emscripten EIO
            throw new Error(message);
        }
        function load(index) {
            if (cache.has(index)) {
                const value = cache.get(index); cache.delete(index); cache.set(index, value);
                return value;
            }
            const start = index * block, end = Math.min(size - 1, start + block - 1);
            const xhr = new XMLHttpRequest();
            // Wine's synchronous POSIX reads require synchronous byte ranges.
            // A binary responseType is forbidden on a window's sync XHR;
            // x-user-defined preserves all bytes through bounded responseText.
            xhr.open('GET', url, false);
            xhr.overrideMimeType('text/plain; charset=x-user-defined');
            xhr.setRequestHeader('Range', 'bytes=' + start + '-' + end);
            try { xhr.send(null); } catch (error) { fail(String(error)); }
            if (xhr.status !== 206 || xhr.getResponseHeader('Content-Range') !==
                'bytes ' + start + '-' + end + '/' + size) fail('Server did not honor exact range');
            const text = xhr.responseText;
            if (text.length !== end - start + 1) fail('Truncated response');
            const bytes = new Uint8Array(text.length);
            for (let i = 0; i < bytes.length; i++) bytes[i] = text.charCodeAt(i) & 255;
            cache.set(index, bytes);
            while (cache.size > limit) cache.delete(cache.keys().next().value);
            return bytes;
        }
        const slash = path.lastIndexOf('/');
        // Emscripten 4's createDataFile returns void, not its created node.
        FS.createDataFile(path.substring(0, slash) || '/', path.substring(slash + 1), new Uint8Array(0), true, false);
        const node = FS.lookupPath(path).node;
        node.usedBytes = size;
        node.stream_ops = Object.assign({}, node.stream_ops, {
            read: function (stream, destination, offset, length, position) {
                if (!Number.isSafeInteger(position) || position < 0 || !Number.isSafeInteger(length) || length < 0 ||
                    !Number.isSafeInteger(offset) || offset < 0 || offset + length > destination.length) fail('Invalid read bounds');
                const wanted = Math.min(length, Math.max(0, size - position));
                let copied = 0;
                while (copied < wanted) {
                    const at = position + copied, index = Math.floor(at / block), within = at - index * block;
                    const bytes = load(index), count = Math.min(bytes.length - within, wanted - copied);
                    destination.set(bytes.subarray(within, within + count), offset + copied);
                    copied += count;
                }
                return copied;
            },
            write: function () { fail('Read-only game archive'); },
            mmap: function () { fail('Game archive mmap is not supported'); }
        });
        return node;
    }
    async function mount(FS, path, url) {
        const response = await fetch(url, {method: 'HEAD'});
        const size = Number(response.headers.get('Content-Length'));
        if (response.status !== 200 || !Number.isSafeInteger(size) || size <= 0) throw new Error('Cannot determine local archive size');
        const node = attach(FS, path, url, size);
        console.log('TonTon archive uses bounded byte ranges: ' + size + ' bytes, 3 MiB cache');
        return node;
    }
    scope.TonTonRangeFile = {attach: attach, mount: mount};
})(typeof globalThis === 'object' ? globalThis : this);
