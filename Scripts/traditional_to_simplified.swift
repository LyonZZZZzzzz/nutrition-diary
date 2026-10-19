#!/usr/bin/env swift
import Foundation
let input = FileHandle.standardInput.readDataToEndOfFile()
let values = (try? JSONDecoder().decode([String].self, from: input)) ?? []
let converted = values.map { value in
    value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value
}
let output = try JSONEncoder().encode(converted)
FileHandle.standardOutput.write(output)
