// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract QiaraEventsV1 {

    // --- Data Structures ---

    struct Data {
        string name; 
        string typeName;  
        bytes value;
    }

    event Vault(string name, Data[] aux);

    function createDataStruct(string memory _name, string memory _typeName, bytes memory _value) public pure returns (Data memory) {
        return Data({name: _name,typeName: _typeName,value: _value});
    }

    function emitVaultEvent(string memory _name, Data[] memory _data) public {
        emit Vault(_name, _data);
    }

}