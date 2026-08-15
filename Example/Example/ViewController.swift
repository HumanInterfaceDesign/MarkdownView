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
        4
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: "Streaming"
        case 1: "Pull Request"
        case 2: "Podcast"
        default: "Diff & Selection"
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 3 ? examples.count : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            config.text = "Streaming Reveal"
            config.secondaryText = "Per-character fade-in as text streams"
        } else if indexPath.section == 1 {
            config.text = "Files Changed"
            config.secondaryText = "Sticky file sections · Expandable context"
        } else if indexPath.section == 2 {
            config.text = "Audio Transcript"
            config.secondaryText = "Preview under audio · Show more · Detail sheet"
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
        let destination: UIViewController = switch indexPath.section {
        case 0: StreamingRevealViewController()
        case 1: SectionedDiffViewController()
        case 2: PodcastTranscriptViewController()
        default: DetailViewController(example: examples[indexPath.row])
        }
        navigationController?.pushViewController(destination, animated: true)
    }
}
