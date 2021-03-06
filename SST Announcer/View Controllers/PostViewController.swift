//
//  PostViewController.swift
//  SST Announcer
//
//  Created by Pan Ziyue on 22/11/16.
//  Copyright © 2016 FourierIndustries. All rights reserved.
//

import UIKit
import DTCoreText
import WebKit
import SnapKit
import SafariServices
import SGNavigationProgress
import TUSafariActivity
import JGProgressHUD

class PostViewController: UIViewController {

  // MARK: - Variables

  var feedObject: FeedItem? {
    didSet {
      // Automatically set title
      self.title = feedObject?.title
    }
  }

  // MARK: - IBOutlets

  @IBOutlet weak var textView: DTAttributedTextView! {
    didSet {
      //textView.textDelegate = self
      textView.shouldDrawImages = true
      textView.contentInset = UIEdgeInsets(top: 16, left: 16, bottom: 32, right: 16)
      textView.textDelegate = self
    }
  }

  @IBOutlet weak var shareBarButtonItem: UIBarButtonItem!

  var webView: WKWebView = WKWebView(frame: CGRect.zero)

  var originalNavigationController: UINavigationController?

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    // Do any additional setup after loading the view.
    navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
    navigationItem.leftItemsSupplementBackButton = true

    guard let feedItem = feedObject else {
      return
    }
    loadFeed(feedItem)

    // Initialise web view
    webView.navigationDelegate = self
    view.addSubview(webView)
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.snp.makeConstraints { make in
      make.edges.equalTo(view.snp.edges)
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // Add KVO for progress to webview
    let keypath = #keyPath(WKWebView.estimatedProgress)
    webView.addObserver(self, forKeyPath: keypath, options: .new, context: nil)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Automatically show popover if device is an iPad in Portrait (size class is reg, reg)
    if let splitViewController = splitViewController {
      let isPortrait = UIInterfaceOrientationIsPortrait(UIApplication.shared.statusBarOrientation)
      if splitViewController.traitCollection.isRR && isPortrait {
        let btn = splitViewController.displayModeButtonItem
        btn.target!.performSelector(onMainThread: btn.action!, with: btn, waitUntilDone: true)
      }
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    navigationController!.cancelSGProgress()
    // Remove observer
    webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    // Remove animation
    if let navController = self.originalNavigationController {
      navController.cancelSGProgress()
    } else {
      self.navigationController?.cancelSGProgress()
    }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    let inset = UIEdgeInsets(top: topLayoutGuide.length, left: 0, bottom: 0, right: 0)
    webView.scrollView.contentInset = inset
    webView.scrollView.scrollIndicatorInsets = inset
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }

  // MARK: - KVO

  // swiftlint:disable:next line_length
  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    if keyPath == #keyPath(WKWebView.estimatedProgress) {
      if webView.estimatedProgress != 1 {
        DispatchQueue.main.async {
          // swiftlint:disable line_length
          if let navController = self.originalNavigationController {
            navController.setSGProgressPercentage(Float(self.webView.estimatedProgress * 100))
          } else {
            self.navigationController?.setSGProgressPercentage(Float(self.webView.estimatedProgress * 100))
          }
          // swiftlint:enable line_length
        }
      } else {
        DispatchQueue.main.async {
          if let navController = self.originalNavigationController {
            navController.finishSGProgress()
          } else {
            self.navigationController?.finishSGProgress()
          }
        }
      }
    } else {
      super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
  }

  // MARK: - Private convienience functions

  private func loadFeed(_ item: FeedItem) {
    if item.rawHtmlContent.hasUndisplayableTraits {
      // Show HUD for better UX
      let hud = JGProgressHUD(style: .dark)!
      hud.interactionType = .blockTouchesOnHUDView
      hud.textLabel.text = "Loading web version..."
      hud.detailTextLabel.text = "This post cannot be optimised"
      hud.show(in: self.navigationController?.view)
      hud.dismiss(afterDelay: 2)
      // Adjust UI element hiding
      webView.isHidden = false
      textView.isHidden = true
      // Load request
      guard let url = URL(string: item.link) else {
        displayError("Unable to open invalid URL: \(item.link)")
        return
      }
      let urlRequest = URLRequest(url: url)
      webView.load(urlRequest)
    } else {
      displayFeedNormally(item)
    }
  }

  private func displayFeedNormally(_ item: FeedItem) {
    webView.isHidden = true
    textView.isHidden = false
    let builderOptions = [
      DTDefaultFontFamily: UIFont.systemFont(ofSize: UIFont.systemFontSize).familyName,
      DTDefaultFontSize: String.getPixelSizeForDynamicType(),
      DTDefaultLineHeightMultiplier: "1.43",
      DTDefaultLinkColor: "#146FDF",
      DTDefaultLinkDecoration: "",
      ]
    guard let htmlData = item.rawHtmlContent.data(using: .utf8) else {
      let errorDescription = "Unable to convert html to data with utf8. Item link: \(item.link)"
      AnnouncerError(type: .unwrapError, errorDescription: errorDescription).relayTelemetry()
      let hud = JGProgressHUD(style: .dark)!
      hud.textLabel.text = "An internal error occured"
      hud.detailTextLabel.text = "Please contact our developers to submit a bug report"
      hud.indicatorView = JGProgressHUDErrorIndicatorView()
      hud.show(in: self.splitViewController?.view ?? self.navigationController?.view)
      hud.dismiss(afterDelay: 3)
      return
    }
    // swiftlint:disable:next line_length
    guard let stringBuilder = DTHTMLAttributedStringBuilder(html: htmlData, options: builderOptions, documentAttributes: nil) else {
      let errorDescription = "Unable to initialize string builder! Item link: \(item.link)"
      AnnouncerError(type: .unwrapError, errorDescription: errorDescription).relayTelemetry()
      let hud = JGProgressHUD(style: .dark)!
      hud.textLabel.text = "An internal error occured"
      hud.detailTextLabel.text = "Please contact our developers to submit a bug report"
      hud.indicatorView = JGProgressHUDErrorIndicatorView()
      hud.show(in: self.splitViewController?.view ?? self.navigationController?.view)
      hud.dismiss(afterDelay: 3)
      return
    }
    textView.attributedString = stringBuilder.generatedAttributedString()
  }

  fileprivate func displayError(_ errString: String) {
    let errorFileName = Bundle.main.path(forResource: "MobileSafariError", ofType: "html")!
    do {
      var errorHtml = try String(contentsOfFile: errorFileName)
      errorHtml = errorHtml.replacingOccurrences(of: "errMsg", with: errString)
      webView.loadHTMLString(errorHtml, baseURL: nil)
    } catch {
      fatalError("Serious error has occured, app unable to locate MobileSafariError.html")
    }
    webView.isHidden = false
    textView.isHidden = true
  }

  // MARK: - IBActions

  @IBAction func shareTapped(_ sender: Any) {
    guard let feedObject = feedObject else {
      return
    }
    guard let url = URL(string: feedObject.link) else {
      return
    }
    let activities = [TUSafariActivity()]
    // swiftlint:disable:next line_length
    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: activities)
    activityVC.popoverPresentationController?.barButtonItem = shareBarButtonItem
    navigationController!.present(activityVC, animated: true, completion: nil)
  }

  /*
   // MARK: - Navigation

   override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
   // Get the new view controller using segue.destinationViewController.
   // Pass the selected object to the new view controller.
   }
   */

}

// MARK: - WKNavigationDelegate

extension PostViewController: WKNavigationDelegate {

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if let navController = originalNavigationController {
      navController.cancelSGProgress()
    } else {
      navigationController?.cancelSGProgress()
    }
    displayError("Unable to open webpage: \(error.localizedDescription)")
  }

  // swiftlint:disable:next line_length
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if let navController = self.originalNavigationController {
      navController.cancelSGProgress()
    } else {
      self.navigationController?.cancelSGProgress()
    }
    displayError("Unable to open webpage: \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    // set progress to 0
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { //0.5 seconds
      if let navController = self.originalNavigationController {
        navController.cancelSGProgress()
      } else {
        self.navigationController?.cancelSGProgress()
      }
    }
  }

}

// MARK: - DTAttributedContentView-related delegates

extension PostViewController: DTAttributedTextContentViewDelegate, DTLazyImageViewDelegate {

  // swiftlint:disable:next line_length
  func attributedTextContentView(_ attributedTextContentView: DTAttributedTextContentView!, viewForLink url: URL!, identifier: String!, frame: CGRect) -> UIView! {
    let linkButton = DTLinkButton(frame: frame)
    linkButton.url = url
    linkButton.addTarget(self, action: #selector(linkPushed(_:)), for: .touchUpInside)
    return linkButton
  }

  // swiftlint:disable:next line_length
  func attributedTextContentView(_ attributedTextContentView: DTAttributedTextContentView!, viewFor attachment: DTTextAttachment!, frame: CGRect) -> UIView! {
    if attachment.isKind(of: DTImageTextAttachment.self) {
      let imageView = DTLazyImageView(frame: frame)
      imageView.delegate = self
      imageView.url = attachment.contentURL
      if attachment.hyperLinkURL != nil {
        imageView.isUserInteractionEnabled = true
        let button = DTLinkButton(frame: imageView.bounds)
        button.url = attachment.hyperLinkURL
        button.minimumHitSize = CGSize(width: 25, height: 25)
        button.guid = attachment.hyperLinkGUID
        button.addTarget(self, action: #selector(linkPushed(_:)), for: .touchUpInside)
        imageView.addSubview(button)
      }
      return imageView
    }
    return nil
  }

  func lazyImageView(_ lazyImageView: DTLazyImageView!, didChangeImageSize size: CGSize) {
    let url = lazyImageView.url!
    var imageSize = size
    var screenSize = view.bounds.size
    screenSize.width -= 32

    if size.width > screenSize.width {
      let ratio = screenSize.width/size.width
      imageSize.width = size.width*ratio
      imageSize.height = size.height*ratio
    }

    let pred = NSPredicate(format: "contentURL == %@", url as CVarArg)

    var didUpdate = false

    guard let layoutFrame = textView.attributedTextContentView.layoutFrame,
          var predicateArray = layoutFrame.textAttachments(with: pred) as? [DTTextAttachment] else {
      let errorDescription = "Unable to predicate text attachment array"
      AnnouncerError(type: .unwrapError, errorDescription: errorDescription).relayTelemetry()
      return
    }

    for index in 0..<predicateArray.count {
      if predicateArray[index].originalSize.equalTo(CGSize.zero) {
        predicateArray[index].originalSize = imageSize
        didUpdate = true
      }
    }

    if didUpdate {
      textView.relayoutText()
    }
  }

  @objc private func linkPushed(_ button: DTLinkButton) {
    guard let url = button.url else {
      let errorDescription = "Unable to unwrap button url: \(button.url.absoluteString))"
      AnnouncerError(type: .unwrapError, errorDescription: errorDescription).relayTelemetry()
      return
    }
    if UIApplication.shared.canOpenURL(url.absoluteURL) {
      let urlString = url.absoluteString
      if urlString.hasPrefix("http") {
        if #available(iOS 9.0, *) {
          let safariViewControler = SFSafariViewController(url: url)
          present(safariViewControler, animated: true, completion: nil)
        } else {
          // Fallback to redirecting the user to Safari
          UIApplication.shared.openURL(url)
        }
      } else if urlString.hasPrefix("mailto") || urlString.hasPrefix("tel") {
        // This is to catch malicious URLs opening unintended apps
        UIApplication.shared.openURL(url)
      }
    } else {
      if url.host == nil && url.path.characters.count == 0 {
        guard let fragment = url.fragment else {
          return
        }
        textView.scroll(toAnchorNamed: fragment, animated: true)
      }
    }
  }

}
