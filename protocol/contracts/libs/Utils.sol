// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Utils {
    function addressListEq(address[] memory list1, address[] memory list2) internal pure returns (bool) {
        uint256 len = list1.length;
        if (list2.length != len) return false;
        for (uint256 i = 0; i < len;) {
            address addr = list2[i];
            if (!addressListContains(list1, addr)) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

    function addressListContains(address[] memory lsit, address addr) internal pure returns (bool) {
        uint256 length = lsit.length;
        for (uint256 i = 0; i < length;) {
            if (lsit[i] == addr) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function uintListContains(uint256[] memory lsit, uint256 v) internal pure returns (bool) {
        uint256 length = lsit.length;
        for (uint256 i = 0; i < length;) {
            if (lsit[i] == v) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function uintListRemove(uint256[] storage list, uint256 v) internal {
        uint256 len = list.length;
        uint256 index;
        for (uint256 i = 0; i < len;) {
            if (list[i] == v) {
                index = (i + 1);
                break;
            }
            unchecked {
                ++i;
            }
        }

        if (index != 0) {
            list[index - 1] = list[len - 1];
            list.pop();
        }
    }

    function bytesEq(bytes memory b1, bytes memory b2) internal pure returns (bool) {
        return keccak256(b1) == keccak256(b2);
    }

    function bytesListContains(bytes[] memory lsit, bytes memory v) internal pure returns (bool) {
        uint256 length = lsit.length;
        for (uint256 i = 0; i < length;) {
            if (bytesEq(lsit[i], v)) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function bytesListRemove(bytes[] storage list, bytes memory v) internal {
        uint256 len = list.length;
        uint256 index;
        for (uint256 i = 0; i < len;) {
            if (bytesEq(list[i], v)) {
                index = (i + 1);
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (index != 0) {
            list[index - 1] = list[len - 1];
            list.pop();
        }
    }

    function fromBytes(bytes memory bys) internal pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    function toBytes(address self) internal pure returns (bytes memory b) {
        b = abi.encodePacked(self);
    }
}
