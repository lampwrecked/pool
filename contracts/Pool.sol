// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
    pool — Lampwrecked
    100 editions. Each edition is ten seconds of one person's touch,
    stored on Ethereum, replayed in the pool one second apart, in order.

    Fully on-chain: the pool itself (compressed HTML) and every gesture
    live in this contract. Each token's animation is assembled here:
    the pool + all gestures, as one self-contained page.

    Free to mint (collectors pay gas). One mint per wallet.
    A token's holder may rewrite its gesture for 0.01 ETH.

    Gesture format (version 1), all integers big-endian:
      [0]      version = 1
      [1..2]   screen aspect × 1000   (100..4000)
      [3]      stroke count           (1..40)
      per stroke:
        [type u8 0..9][fingers u8 1..5]
        per finger:
          [n u16 ≥1][t0 u16 ms 0..10000][x u16][y u16]
          then (n-1) × [dt u8 ms][x u16][y u16]
      x, y are 0..1000 across / down the screen.
*/

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract Pool is ERC721, ERC2981, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 100;
    uint256 public constant MAX_BYTES = 6144;
    uint256 public constant MAX_STROKES = 40;
    uint256 public constant MAX_MS = 10000;
    uint256 public constant REWRITE_PRICE = 0.01 ether;

    uint8 public constant FILE_POOL = 0; // the pool, gzipped HTML
    uint8 public constant FILE_MINT = 1; // the mint page, gzipped HTML

    uint256 public totalSupply;
    bool public mintOpen;
    bool public rewriteOpen = true;
    bool public filesFrozen;

    mapping(address => bool) public hasMinted;
    mapping(uint256 => address) private _data;      // token id => contract holding its gesture
    mapping(uint8 => address[]) private _files;     // file slot => chunks

    event Gesture(uint256 indexed tokenId, address indexed by, uint256 size, bool rewrite);
    // ERC-4906: tell marketplaces to refresh. Every token's animation holds every gesture,
    // so any change refreshes them all.
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    constructor() ERC721("pool", "POOL") Ownable(msg.sender) {}

    // ------------------------------------------------------------ mint + rewrite

    function mint(bytes calldata g) external returns (uint256 id) {
        require(mintOpen, "mint closed");
        require(totalSupply < MAX_SUPPLY, "pool is full");
        require(!hasMinted[msg.sender], "one gesture per wallet");
        _validate(g);

        hasMinted[msg.sender] = true;
        id = ++totalSupply;
        _data[id] = _store(g);
        _mint(msg.sender, id);
        emit Gesture(id, msg.sender, g.length, false);
        if (id > 1) emit BatchMetadataUpdate(1, id - 1);
    }

    /// replace your token's gesture. It keeps its number and its place in the order.
    function rewrite(uint256 id, bytes calldata g) external payable {
        require(rewriteOpen, "rewrites closed");
        require(ownerOf(id) == msg.sender, "not your token");
        require(msg.value == REWRITE_PRICE, "rewrite costs 0.01 ETH");
        _validate(g);
        _data[id] = _store(g);
        emit Gesture(id, msg.sender, g.length, true);
        emit BatchMetadataUpdate(1, totalSupply);
    }

    function _validate(bytes calldata g) internal pure {
        uint256 len = g.length;
        require(len >= 12 && len <= MAX_BYTES, "bad size");
        require(uint8(g[0]) == 1, "bad version");
        uint256 aspect = _u16(g, 1);
        require(aspect >= 100 && aspect <= 4000, "bad aspect");
        uint256 strokes = uint8(g[3]);
        require(strokes >= 1 && strokes <= MAX_STROKES, "bad strokes");
        uint256 p = 4;
        for (uint256 s; s < strokes; ++s) {
            require(p + 2 <= len, "truncated");
            require(uint8(g[p]) <= 9, "bad type");
            uint256 fingers = uint8(g[p + 1]);
            require(fingers >= 1 && fingers <= 5, "bad fingers");
            p += 2;
            for (uint256 f; f < fingers; ++f) {
                require(p + 8 <= len, "truncated");
                uint256 n = _u16(g, p);
                require(n >= 1, "empty finger");
                require(_u16(g, p + 2) <= MAX_MS, "too late");
                p += 8 + (n - 1) * 5;
                require(p <= len, "truncated");
            }
        }
        require(p == len, "trailing bytes");
    }

    function _u16(bytes calldata g, uint256 i) private pure returns (uint256) {
        return (uint256(uint8(g[i])) << 8) | uint256(uint8(g[i + 1]));
    }

    // data is deployed as the code of a tiny contract (cheaper than storage, permanent)
    function _store(bytes memory g) private returns (address ptr) {
        require(g.length < 24575, "chunk too big");
        bytes memory code = abi.encodePacked(hex"63", uint32(g.length + 1), hex"80600E6000396000F3", hex"00", g);
        assembly {
            ptr := create(0, add(code, 32), mload(code))
        }
        require(ptr != address(0), "store failed");
    }

    function _load(address ptr) private view returns (bytes memory out) {
        uint256 size = ptr.code.length - 1;
        out = new bytes(size);
        assembly {
            extcodecopy(ptr, add(out, 32), 1, size)
        }
    }

    // ------------------------------------------------------------ read

    function gesture(uint256 id) public view returns (bytes memory) {
        require(id >= 1 && id <= totalSupply, "no such gesture");
        return _load(_data[id]);
    }

    /// gestures from `from` (1-based), up to `count` of them
    function gestures(uint256 from, uint256 count) external view returns (bytes[] memory list) {
        if (from < 1) from = 1;
        if (count == 0 || from > totalSupply) return new bytes[](0);
        uint256 end = from + count - 1;
        if (end > totalSupply) end = totalSupply;
        list = new bytes[](end - from + 1);
        for (uint256 i; i < list.length; ++i) list[i] = gesture(from + i);
    }

    /// token ids held by `who`
    function tokensOf(address who) external view returns (uint256[] memory ids) {
        uint256 n;
        for (uint256 i = 1; i <= totalSupply; ++i) if (_ownerOf(i) == who) ++n;
        ids = new uint256[](n);
        n = 0;
        for (uint256 i = 1; i <= totalSupply; ++i) if (_ownerOf(i) == who) ids[n++] = i;
    }

    function file(uint8 slot) public view returns (bytes memory) {
        address[] storage chunks = _files[slot];
        bytes[] memory parts = new bytes[](chunks.length);
        for (uint256 i; i < chunks.length; ++i) parts[i] = _load(chunks[i]);
        return _cat(parts);
    }

    // ------------------------------------------------------------ the artwork

    /// the pool as one self-contained HTML page. token 0 = the whole pool, no edition highlighted
    function poolHTML(uint256 token) public view returns (bytes memory) {
        uint256 n = totalSupply;
        bytes[] memory parts = new bytes[](n * 2 + 3);
        parts[0] = abi.encodePacked('{"token":', token.toString(), ',"gestures":[');
        for (uint256 i = 1; i <= n; ++i) {
            parts[i * 2 - 1] = bytes(Base64.encode(gesture(i)));
            parts[i * 2] = bytes(i < n ? '","' : "");
        }
        if (n > 0) { parts[1] = abi.encodePacked('"', parts[1]); parts[n * 2] = '"'; }
        parts[n * 2 + 1] = "]}";
        return _page(file(FILE_POOL), "/*POOL_DATA*/null", _cat(parts));
    }

    /// the mint page, wired to this contract, straight from the chain
    function mintHTML() public view returns (bytes memory) {
        bytes memory cfg = abi.encodePacked(
            '{"contract":"', Strings.toHexString(address(this)), '","chainId":', block.chainid.toString(), "}"
        );
        return _page(file(FILE_MINT), "/*POOL_CONFIG*/null", cfg);
    }

    // a tiny loader: unzips the stored page in the browser and drops the data in
    function _page(bytes memory gz, string memory key, bytes memory data) private pure returns (bytes memory) {
        require(gz.length > 0, "file not uploaded yet");
        bytes[] memory p = new bytes[](7);
        p[0] = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover"><title>pool</title><style>html,body{margin:0;height:100%;background:#000}</style></head><body><script>(async()=>{const k="';
        p[1] = bytes(key);
        p[2] = '",d=';
        p[3] = data;
        p[4] = ',z="';
        p[5] = bytes(Base64.encode(gz));
        p[6] = '";const b=Uint8Array.from(atob(z),c=>c.charCodeAt(0));let h=await new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream("gzip"))).text();h=h.split(k).join(JSON.stringify(d));document.open();document.write(h);document.close()})()</script></body></html>';
        return _cat(p);
    }

    // ------------------------------------------------------------ metadata

    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        bytes[] memory p = new bytes[](9);
        p[0] = abi.encodePacked('{"name":"pool #', id.toString());
        p[1] = '","description":"Ten seconds of touch, released into a pool of light with ninety-nine others. Replayed in order, one second apart. Fully on-chain. pool by Lampwrecked.","image":"data:image/svg+xml;base64,';
        p[2] = bytes(Base64.encode(_svg(id)));
        if (_files[FILE_POOL].length > 0) {
            p[3] = '","animation_url":"data:text/html;base64,';
            p[4] = bytes(Base64.encode(poolHTML(id)));
        }
        p[5] = '","attributes":[{"trait_type":"Order","value":';
        p[6] = bytes(id.toString());
        p[7] = "}]";
        p[8] = "}";
        return string.concat("data:application/json;base64,", Base64.encode(_cat(p)));
    }

    // a still of the gesture: every finger path traced in light on black water
    function _svg(uint256 id) internal view returns (bytes memory) {
        bytes memory g = gesture(id);
        uint256 aspect = (uint256(uint8(g[1])) << 8) | uint8(g[2]);
        uint256 h = 860;
        uint256 w = (h * aspect) / 1000;
        if (w > 860) { w = 860; h = (860 * 1000) / aspect; }
        uint256 ox = (1000 - w) / 2;
        uint256 oy = (1000 - h) / 2;

        bytes memory b = new bytes(g.length * 8 + 1600);
        uint256 k = _put(b, 0,
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">',
                '<rect width="1000" height="1000" fill="#dfe8ea"/><rect x="24" y="24" width="952" height="952" fill="#020a10"/>',
                '<rect x="', ox.toString(), '" y="', oy.toString(), '" width="', w.toString(), '" height="', h.toString(),
                '" fill="none" stroke="#0e2a36" stroke-width="2"/>',
                '<g fill="none" stroke="#5fe3ff" stroke-opacity=".85" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">'
            ));

        uint256 strokes = uint8(g[3]);
        uint256 p = 4;
        for (uint256 s; s < strokes; ++s) {
            uint256 fingers = uint8(g[p + 1]);
            p += 2;
            for (uint256 f; f < fingers; ++f) {
                uint256 n = (uint256(uint8(g[p])) << 8) | uint8(g[p + 1]);
                uint256 q = p + 4;
                k = _put(b, k, bytes('<polyline points="'));
                for (uint256 i; i < n; ++i) {
                    uint256 x = (uint256(uint8(g[q])) << 8) | uint8(g[q + 1]);
                    uint256 y = (uint256(uint8(g[q + 2])) << 8) | uint8(g[q + 3]);
                    if (x > 1000) x = 1000;
                    if (y > 1000) y = 1000;
                    k = _num(b, k, ox + (x * w) / 1000); b[k++] = ",";
                    k = _num(b, k, oy + (y * h) / 1000); b[k++] = " ";
                    q += 5; // next point: [dt][x][y], so its x sits 5 bytes on
                }
                k = _put(b, k, bytes('"/>'));
                p += 8 + (n - 1) * 5;
            }
        }
        k = _put(b, k, bytes("</g></svg>"));
        assembly { mstore(b, k) }
        return b;
    }

    // ------------------------------------------------------------ memory helpers

    /// join byte arrays with one allocation (keeps big pages cheap to build)
    function _cat(bytes[] memory parts) private pure returns (bytes memory out) {
        uint256 total;
        for (uint256 i; i < parts.length; ++i) total += parts[i].length;
        out = new bytes(total);
        uint256 dst;
        assembly { dst := add(out, 32) }
        for (uint256 i; i < parts.length; ++i) {
            bytes memory src = parts[i];
            assembly {
                let len := mload(src)
                let s := add(src, 32)
                for { let j := 0 } lt(j, len) { j := add(j, 32) } { mstore(add(dst, j), mload(add(s, j))) }
                dst := add(dst, len)
            }
        }
    }

    function _put(bytes memory b, uint256 k, bytes memory s) private pure returns (uint256) {
        for (uint256 i; i < s.length; ++i) b[k++] = s[i];
        return k;
    }

    function _num(bytes memory b, uint256 k, uint256 v) private pure returns (uint256) {
        if (v >= 1000) { b[k++] = bytes1(uint8(48 + v / 1000)); }
        if (v >= 100) { b[k++] = bytes1(uint8(48 + (v / 100) % 10)); }
        if (v >= 10) { b[k++] = bytes1(uint8(48 + (v / 10) % 10)); }
        b[k++] = bytes1(uint8(48 + v % 10));
        return k;
    }

    // ------------------------------------------------------------ artist

    /// upload (or replace) a file. Big files: send the first chunk with `replace`, then append the rest.
    function writeFile(uint8 slot, bytes calldata chunk, bool replace) external onlyOwner {
        require(!filesFrozen, "files frozen");
        if (replace) delete _files[slot];
        _files[slot].push(_store(chunk));
        if (totalSupply > 0) emit BatchMetadataUpdate(1, totalSupply);
    }

    /// permanent: the pool and mint page can never change again
    function freezeFiles() external onlyOwner { filesFrozen = true; }

    function setMintOpen(bool open) external onlyOwner { mintOpen = open; }
    function setRewriteOpen(bool open) external onlyOwner { rewriteOpen = open; }
    function setRoyalty(address to, uint96 bps) external onlyOwner { _setDefaultRoyalty(to, bps); }

    function withdraw() external onlyOwner {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    function supportsInterface(bytes4 id) public view override(ERC721, ERC2981) returns (bool) {
        return id == 0x49064906 || super.supportsInterface(id);
    }
}
