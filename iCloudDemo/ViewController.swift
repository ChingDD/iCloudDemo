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
    let viewModel: DatabaseViewModel

    init(viewModel: DatabaseViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()
        binding()
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

    private func binding() {
        viewModel.item.bind { items in
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    @objc private func refreshData() {
        self.tableView.reloadData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
    }
    
    @objc func add() {
        let controller = AddViewController(viewModel: viewModel)
        controller.configForAdd()
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc func share() {
        if let share = viewModel.database.share {
            let rootRecord = viewModel.database.rootShareRecord
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
                    let controller = UICloudSharingController(share: share, container: self.viewModel.database.container)
                    controller.availablePermissions = [.allowReadWrite, .allowPrivate]
                    controller.delegate = self

                    self.present(controller, animated: true)
                    print("Share created successfully with stable URL")
                }
            }
            self.viewModel.startOperation(op: op)

        } else {
            print("Share is nil")
        }
    }
}


extension ViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let items = viewModel.item.value ?? []
        let item = items[indexPath.row]

        let controller = AddViewController(viewModel: viewModel)
        controller.configForEdit(item: item, index: indexPath.row)
        navigationController?.pushViewController(controller, animated: true)
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteButton = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (action, view, completionHandler) in
            guard let self else { return }
            let items = viewModel.item.value ?? []
            let item = items[indexPath.row]
            viewModel.deleteData(data: item, index: indexPath.row)
        }
        let config = UISwipeActionsConfiguration(actions: [deleteButton])
        return config
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let items = viewModel.item.value ?? []
        return items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let items = viewModel.item.value ?? []
        cell.textLabel?.text = items[indexPath.row].title
        return cell
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
