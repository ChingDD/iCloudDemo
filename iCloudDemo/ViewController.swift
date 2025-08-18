//
//  ViewController.swift
//  iCloudDemo
//
//  Created by 林仲景 on 2025/8/11.
//

import UIKit

class ViewController: UIViewController {
    let tableView = UITableView()
    var dataList: [Item] = []
    let cloudMgr = CloudSyncMgr.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.// fetch data
        CloudSyncMgr.shared.fetchRecords { [weak self] items in
            guard let items else {
                print("cloud item is nil")
                return
            }
            DispatchQueue.main.async {
                self?.dataList = items
                self?.tableView.reloadData()
            }
        }
        
        view.backgroundColor = .red
        view.addSubview(tableView)
        
        title = "iCloud Demo"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
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
}


extension ViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let controller = AddViewController()
        controller.delegate = self
        let item = dataList[indexPath.row]
        controller.configForEdit(title: item.title, index: indexPath.row, share: item.isShare)
        navigationController?.pushViewController(controller, animated: true)
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteButton = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (action, view, completionHandler) in
            self?.dataList.remove(at: indexPath.row)
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
    func didEditItem(at index: Int, with text: String, isSelect: Bool) {
        if index < dataList.count {
            dataList[index] = Item(title: text, isShare: isSelect)
            tableView.reloadData()
        }
    }
    
    func didAddItem(_ text: String, isSelect: Bool) {
        let newItem = Item(title: text, isShare: isSelect)
        dataList.append(newItem)
        tableView.reloadData()
    }
}

