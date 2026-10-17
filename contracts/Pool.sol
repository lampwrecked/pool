// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
    pool — Lampwrecked
    100 editions. Each edition is ten seconds of one person's touch,
    stored on Ethereum, replayed in the pool one second apart.

    Free to mint (collectors pay gas). One gesture per wallet.

    Gesture format (version 1), all integers big-endian:
      [0]      version = 1
      [1..2]   screen aspect × 1000   (100..4000)
      [3]      stroke count           (1..40)
      per stroke:
        [type u8 0..9][fingers u8 1..5]
        per finger:
          [n u16 ≥1][t0 u16 ms 0..10000][x u16][y u16]
          then (n-1) × [dt u8 ms][x u16][y u16]
      x, y are 0..1000 across / down the phone screen.
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

    uint256 public totalSupply;
    bool public mintOpen;
    bool public metadataFrozen;
    string public animationBase; // e.g. https://pool.lampwrecked.art/pool/

    mapping(address => bool) public hasMinted;
    mapping(uint256 => address) private _data; // token id => contract holding the gesture bytes

    event Gesture(uint256 indexed tokenId, address indexed by, uint256 size);

    constructor() ERC721("pool", "POOL") Ownable(msg.sender) {}

    // ------------------------------------------------------------ mint

    function mint(bytes calldata g) external returns (uint256 id) {
        require(mintOpen, "mint closed");
        require(totalSupply < MAX_SUPPLY, "pool is full");
        require(!hasMinted[msg.sender], "one gesture per wallet");
        _validate(g);

        hasMinted[msg.sender] = true;
        id = ++totalSupply;
        _data[id] = _store(g);
        _mint(msg.sender, id);
        emit Gesture(id, msg.sender, g.length);
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

    // gesture bytes are deployed as the code of a tiny contract (cheaper than storage, permanent)
    function _store(bytes calldata g) private returns (address ptr) {
        bytes memory code = abi.encodePacked(
            hex"63", uint32(g.length + 1), hex"80600E6000396000F3", hex"00", g
        );
        assembly {
            ptr := create(0, add(code, 32), mload(code))
        }
        require(ptr != address(0), "store failed");
    }

    // ------------------------------------------------------------ read

    function gesture(uint256 id) public view returns (bytes memory out) {
        require(id >= 1 && id <= totalSupply, "no such gesture");
        address ptr = _data[id];
        uint256 size = ptr.code.length - 1;
        out = new bytes(size);
        assembly {
            extcodecopy(ptr, add(out, 32), 1, size)
        }
    }

    /// gestures from `from` (1-based), up to `count` of them — the pool page reads these
    function gestures(uint256 from, uint256 count) external view returns (bytes[] memory list) {
        if (from < 1) from = 1;
        uint256 end = from + count - 1;
        if (end > totalSupply) end = totalSupply;
        if (count == 0 || from > end) return new bytes[](0);
        list = new bytes[](end - from + 1);
        for (uint256 i; i < list.length; ++i) list[i] = gesture(from + i);
    }

    // ------------------------------------------------------------ metadata

    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        string memory svg = Base64.encode(_svg(id));
        string memory anim = bytes(animationBase).length == 0
            ? ""
            : string.concat(',"animation_url":"', animationBase, "?token=", id.toString(), '"');
        bytes memory json = abi.encodePacked(
            '{"name":"pool #', id.toString(),
            '","description":"Ten seconds of touch, released into a pool of light with ninety-nine others. Replayed in order, one second apart. pool by Lampwrecked.",',
            '"image":"data:image/svg+xml;base64,', svg, '"', anim,
            ',"attributes":[{"trait_type":"Order","value":', id.toString(), "}]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(json));
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

    function setMintOpen(bool open) external onlyOwner { mintOpen = open; }

    function setAnimationBase(string calldata base) external onlyOwner {
        require(!metadataFrozen, "frozen");
        animationBase = base;
    }

    /// permanent: the animation link can never change again
    function freezeMetadata() external onlyOwner { metadataFrozen = true; }

    function setRoyalty(address to, uint96 bps) external onlyOwner { _setDefaultRoyalty(to, bps); }

    function supportsInterface(bytes4 id) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(id);
    }
}
