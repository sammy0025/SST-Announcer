//
//  MainTableViewController.swift
//  SST Announcer
//
//  Created by Pan Ziyue on 22/11/16.
//  Copyright © 2016 Pan Ziyue. All rights reserved.
//

import UIKit
import SGNavigationProgress

class MainTableViewController: UITableViewController {

    // MARK: - Variables

    fileprivate var collapseDetailViewController = true //When selected, this should turn false

    fileprivate var feeder = Feeder()
    fileprivate var filteredFeeds: [FeedItem] = []
    /// A `FeedItem` object that is pushed from push notifications
    private var pushedFeedItem: FeedItem?

    fileprivate var searchController: UISearchController = {
        let searchCtrl = UISearchController(searchResultsController: nil)
        searchCtrl.hidesNavigationBarDuringPresentation = false
        searchCtrl.dimsBackgroundDuringPresentation = false
        searchCtrl.searchBar.barStyle = .default
        return searchCtrl
    }()

    /// Progress tracking for UI only, loading will not actually be cancelled
    fileprivate var progressCancelled = false

    /// Computed property to check if the search controller is active
    fileprivate var searchControllerActive: Bool {
        return self.searchController.isActive && self.searchController.searchBar.text!.characters.count > 0
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.splitViewController!.delegate = self
        self.splitViewController!.preferredDisplayMode = .automatic

        // Set navigation bar to the search bar and set delegates
        self.navigationItem.titleView = self.searchController.searchBar
        self.searchController.delegate = self
        self.searchController.searchResultsUpdater = self
        self.searchController.searchBar.delegate = self

        // Start loading feeds asynchronously
        feeder.delegate = self
        feeder.requestFeedsAsynchronous()
        self.navigationController!.setSGProgressPercentage(5) //for UX reasons

        // Add peek and pop
        if #available(iOS 9.0, *) {
            if self.traitCollection.forceTouchCapability == .available {
                self.registerForPreviewing(with: self, sourceView: view)
            }
        } else {
            // Fallback on earlier versions
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.progressCancelled = true
        self.navigationController!.cancelSGProgress()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.searchControllerActive {
            return self.filteredFeeds.count
        }
        return self.feeder.feeds.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "postcell", for: indexPath) as? PostTableViewCell else {
            fatalError("Unable to cast tableView's cell as a PostTableViewCell!")
        }

        // Configure the cell...
        if self.searchControllerActive {
            let currentFeedObject = self.filteredFeeds[indexPath.row]
            cell.titleLabel.text = currentFeedObject.title
            cell.dateLabel.text = currentFeedObject.date.decodeToTimeAgo()
            cell.descriptionLabel.text = currentFeedObject.strippedHtmlContent
        } else {
            let currentFeedObject = self.feeder.feeds[indexPath.row]
            cell.titleLabel.text = currentFeedObject.title
            cell.dateLabel.text = currentFeedObject.date.decodeToTimeAgo()
            cell.descriptionLabel.text = currentFeedObject.strippedHtmlContent
        }
        cell.dateWidthConstraint.constant = cell.dateLabel.intrinsicContentSize.width

        return cell
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "presentPostFromMain" {
            if let navController = segue.destination as? UINavigationController {
                guard let postViewController = navController.topViewController as? PostViewController else {
                    fatalError("Unable to unwrap navController topview as PostViewController")
                }
                if let selectedIndexPath = self.tableView.indexPathForSelectedRow {
                    if self.searchControllerActive {
                        let selectedPost = self.filteredFeeds[selectedIndexPath.row]
                        postViewController.feedObject = selectedPost
                    } else {
                        let selectedPost = self.feeder.feeds[selectedIndexPath.row]
                        postViewController.feedObject = selectedPost
                    }
                    let viewIsCR = self.traitCollection.horizontalSizeClass == .compact && self.traitCollection.verticalSizeClass == .regular
                    let viewIsCC = self.traitCollection.horizontalSizeClass == .compact && self.traitCollection.verticalSizeClass == .compact
                    if viewIsCR || viewIsCC {
                        postViewController.originalNavigationController = self.navigationController
                    }
                } else {
                    // The application initiated the segue from a push notification
                    //TODO: Implement push-based segue
                    guard let feedItem = self.pushedFeedItem else {
                        //TODO: Send telemetry data for the problem
                        return
                    }
                    postViewController.feedObject = feedItem
                }
            }
        }
    }

}

// MARK: - UISplitViewControllerDelegate

extension MainTableViewController: UISplitViewControllerDelegate {

    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        return collapseDetailViewController
    }

}

// MARK: - FeederDelegate

extension MainTableViewController: FeederDelegate {

    func feedLoadedPercent(_ percent: Float) {
        if !progressCancelled {
            let percentageInHundred = percent * 100
            DispatchQueue.main.async {
                self.navigationController!.setSGProgressPercentage(percentageInHundred)
            }
        }
    }

    func feedFinishedParsing(withFeedArray feedArray: [FeedItem]?, error: Error?) {
        self.progressCancelled = false
        if let error = error {
            // Parse error here
            switch error {
            case AnnouncerError.networkError:
                print("Network error occured")
            default:
                print("Error occured")
            }
        } else {
            // No error occured
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }

}

// MARK: - UISearch-related delegates

extension MainTableViewController: UISearchControllerDelegate, UISearchResultsUpdating, UISearchBarDelegate {

    func updateSearchResults(for searchController: UISearchController) {
        self.filter(forSearchText: searchController.searchBar.text!)
    }

    private func filter(forSearchText searchText: String) {
        self.filteredFeeds = self.feeder.feeds.filter { feed in
            return feed.title.lowercased().contains(searchText.lowercased())
        }
        self.tableView.reloadData()
    }

}

// MARK: - UIViewcontrollerPreviewingDelegate

@available(iOS 9.0, *) //only available on iOS 9 and above
extension MainTableViewController: UIViewControllerPreviewingDelegate {

    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard let indexPath = self.tableView.indexPathForRow(at: location) else { return nil }
        guard let cell = self.tableView.cellForRow(at: indexPath) else { return nil }
        guard let detailVcNavController = self.storyboard!.instantiateViewController(withIdentifier: "PostNavigationController") as? UINavigationController else { return nil }
        guard let detailVc = detailVcNavController.topViewController as? PostViewController else { return nil }
        if self.searchControllerActive {
            detailVc.feedObject = self.filteredFeeds[indexPath.row]
        } else {
            detailVc.feedObject = self.feeder.feeds[indexPath.row]
        }
        let viewIsCR = self.traitCollection.horizontalSizeClass == .compact && self.traitCollection.verticalSizeClass == .regular
        let viewIsCC = self.traitCollection.horizontalSizeClass == .compact && self.traitCollection.verticalSizeClass == .compact
        if viewIsCR || viewIsCC {
            detailVc.originalNavigationController = self.navigationController
        }
        previewingContext.sourceRect = cell.frame
        return detailVcNavController
    }

    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        self.show(viewControllerToCommit, sender: self)
    }

}
