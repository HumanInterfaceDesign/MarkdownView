//
//  DiffExample.swift
//  Example
//
//  Created by Gary Tokman on 3/26/26.
//

import Foundation

struct DiffExample {
    let title: String
    let subtitle: String
    let markdown: String
}

let examples: [DiffExample] = [
    DiffExample(
        title: "Rename Refactor",
        subtitle: "Swift class rename",
        markdown: """
        ```diff swift
        @@ -1,6 +1,6 @@
        -class DesignEngineer {
        +class Designer {
             let name: String
        -    func engineerTitle() -> String {
        +    func designerTitle() -> String {
                 return name
             }
         }
        ```
        """
    ),
    DiffExample(
        title: "Bug Fix",
        subtitle: "Off-by-one error in Python",
        markdown: """
        ```diff python
        @@ -3,7 +3,7 @@
         def binary_search(arr, target):
             lo, hi = 0, len(arr) - 1
             while lo <= hi:
        -        mid = (lo + hi) / 2
        +        mid = (lo + hi) // 2
                 if arr[mid] == target:
                     return mid
                 elif arr[mid] < target:
        ```
        """
    ),
    DiffExample(
        title: "Add Logging",
        subtitle: "TypeScript API handler",
        markdown: """
        ```diff typescript
        @@ -8,6 +8,8 @@
         export async function handler(req: Request) {
             const { userId } = req.params;
        +    console.log(`Fetching user: ${userId}`);
             const user = await db.users.findById(userId);
             if (!user) {
        +        console.warn(`User not found: ${userId}`);
                 return Response.notFound();
             }
        ```
        """
    ),
    DiffExample(
        title: "Config Change",
        subtitle: "JSON configuration update",
        markdown: """
        ```diff json
        @@ -2,5 +2,6 @@
         {
             "name": "my-app",
        -    "version": "1.2.0",
        +    "version": "1.3.0",
             "private": true,
        +    "license": "MIT"
         }
        ```
        """
    ),
    DiffExample(
        title: "SQL Migration",
        subtitle: "Add index and column",
        markdown: """
        ```diff sql
        @@ -1,4 +1,6 @@
         CREATE TABLE users (
             id SERIAL PRIMARY KEY,
        -    name TEXT NOT NULL
        +    name TEXT NOT NULL,
        +    email TEXT UNIQUE NOT NULL,
        +    created_at TIMESTAMPTZ DEFAULT NOW()
         );
        ```
        """
    ),
]
