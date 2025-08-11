//
//  ViewController.swift
//  iCloudDemo
//
//  Created by 林仲景 on 2025/8/11.
//

import UIKit

class ViewController: UIViewController {
    let tableView = UITableView()
    var dataList: [String] = []
    let cloudMgr = CloudeSyncMgr.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        view.backgroundColor = .red
        view.addSubview(tableView)
        
        title = "iCloud Demo"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.reloadData()
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
        controller.configForEdit(title: dataList[indexPath.row], index: indexPath.row)
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
        cell.textLabel?.text = dataList[indexPath.row]
        return cell
    }
}

extension ViewController: AddViewControllerDelegate {
    func didAddItem(_ text: String) {
        dataList.append(text)
        tableView.reloadData()
    }
    
    func didEditItem(at index: Int, with text: String) {
        if index < dataList.count {
            dataList[index] = text
            tableView.reloadData()
        }
    }
}

