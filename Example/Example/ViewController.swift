//
//  ViewController.swift
//  Example
//
//  Created by Gary Tokman on 3/26/26.
//

import UIKit

class ViewController: UITableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "MarkdownView Examples"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Streaming" : "Diff & Selection"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : examples.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            config.text = "Streaming Reveal"
            config.secondaryText = "Per-character fade-in as text streams"
        } else {
            let example = examples[indexPath.row]
            config.text = example.title
            config.secondaryText = example.subtitle
        }
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let destination: UIViewController
        if indexPath.section == 0 {
            destination = StreamingRevealViewController()
        } else {
            destination = DetailViewController(example: examples[indexPath.row])
        }
        navigationController?.pushViewController(destination, animated: true)
    }
}
