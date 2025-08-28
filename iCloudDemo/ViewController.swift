//
//  ViewController.swift
//  iCloudDemo
//
//  Created by 林仲景 on 2025/8/11.
//

import UIKit
import CloudKit

class ViewController: UIViewController {
    let tableView = UITableView()
    var dataList: [Item] = []
    let cloudMgr = CloudSyncMgr.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNotifications()
        loadData()
    }
    
    private func setupUI() {
        view.backgroundColor = .red
        view.addSubview(tableView)
        
        title = "iCloud Demo"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share))

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshData),
            name: .init("RefreshData"),
            object: nil
        )
    }
    
    private func loadData() {
        CloudSyncMgr.shared.performAfterInitialization { [weak self] in
            CloudSyncMgr.shared.fetchRecords(database: .private) { [weak self] items in
                CloudSyncMgr.shared.fetchRecords(database: .shared) { [weak self] sharedItems in
                    DispatchQueue.main.async {
                        self?.dataList.removeAll()
                        
                        if let items {
                            self?.dataList.append(contentsOf: items)
                        }

                        if let sharedItems {
                            self?.dataList.append(contentsOf: sharedItems)
                        }

                        self?.tableView.reloadData()
                    }
                }
            }
        }
    }
    
    @objc private func refreshData() {
        loadData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
    }
    
    @objc func add() {
        let controller = AddViewController()
        controller.delegate = self
        controller.configForAdd()
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc func share() {
        if let rootRecord = CloudSyncMgr.shared.rootShareRecord, let share = CloudSyncMgr.shared.share {
            let op = CKModifyRecordsOperation(recordsToSave: [rootRecord, share], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.modifyRecordsCompletionBlock = { records, recordIDs, error in
                DispatchQueue.main.async {
                    guard error == nil else {
                        print("Share Fail: \(String(describing: error))")
                        return
                    }

                    // CloudKit 成功儲存 share 後會自動分配 stable share URL
                    // 使用 UICloudSharingController 來管理參與者和權限，並分發 share URL
                    let controller = UICloudSharingController(share: share, container: CloudSyncMgr.shared.container)
                    controller.availablePermissions = [.allowReadWrite, .allowPrivate]
                    controller.delegate = self

                    self.present(controller, animated: true)
                    print("Share created successfully with stable URL")
                }
            }

            CloudSyncMgr.shared.container.privateCloudDatabase.add(op)
        } else {
            print("Share Fail: root record \(CloudSyncMgr.shared.rootShareRecord), share: \(CloudSyncMgr.shared.share)")
        }
    }
}


extension ViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let controller = AddViewController()
        controller.delegate = self
        let item = dataList[indexPath.row]
        controller.configForEdit(item: item, index: indexPath.row)
        navigationController?.pushViewController(controller, animated: true)
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteButton = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (action, view, completionHandler) in
            guard let self else { return }
            CloudSyncMgr.shared.deleteToCloud(readyToDelete: self.dataList[indexPath.row])
            self.dataList.remove(at: indexPath.row)
            tableView.reloadData()
        }
        let config = UISwipeActionsConfiguration(actions: [deleteButton])
        return config
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        dataList.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = dataList[indexPath.row].title
        return cell
    }
}

extension ViewController: AddViewControllerDelegate {
    func didAddItem(item: Item) {
        // 重新載入資料以確保同步最新狀態
        self.dataList.append(item)
        tableView.reloadData()
    }
    
    func didEditItem(at index: Int, item: Item) {
        // 重新載入資料以確保同步最新狀態  
        self.dataList.append(item)
        tableView.reloadData()
    }
}


extension ViewController: UICloudSharingControllerDelegate {
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
        print("share error: \(error)")
    }
    
    func itemTitle(for csc: UICloudSharingController) -> String? {
        return nil
    }
}
