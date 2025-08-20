//
//  AddViewController.swift
//  iCloudDemo
//
//  Created by 林仲景 on 2025/8/11.
//

import UIKit
protocol AddViewControllerDelegate: AnyObject {
    func didAddItem(item: Item)
    func didEditItem(at index: Int, item: Item)
}

class AddViewController: UIViewController {
    let textField = UITextField()
    let button = UIButton()
    let shareButton = UIButton()

    var currentItem = Item()

    weak var delegate: AddViewControllerDelegate?
    
    var editingIndex: Int?
    var isEditingMode: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        textField.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        textField.textAlignment = .center
        textField.font = .systemFont(ofSize: 28)
        textField.textColor = .black
        textField.layer.borderColor = UIColor.black.cgColor
        textField.layer.borderWidth = 3
        textField.delegate = self
        view.addSubview(textField)

        var config = UIButton.Configuration.filled()
        config.title = "Yes"
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        button.configuration = config
        button.frame = CGRect(x: 0, y: 0, width: 150, height: 50)
        button.addTarget(self, action: #selector(tapButton), for: .touchUpInside)
        view.addSubview(button)
        
        var shareConfig = UIButton.Configuration.plain()
        shareConfig.title = "Share"
        shareConfig.baseBackgroundColor = .white
        shareConfig.baseForegroundColor = .black
        shareConfig.image = currentItem.isShare ? UIImage(systemName: "square.fill") : UIImage(systemName: "square.dotted")
        shareConfig.imagePlacement = .leading
        shareButton.configuration = shareConfig
        shareButton.frame = CGRect(x: 0, y: 0, width: 150, height: 25)
        shareButton.addTarget(self, action: #selector(tapShareButton), for: .touchUpInside)
        view.addSubview(shareButton)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        textField.center = view.center
        button.center.x = textField.center.x
        button.frame.origin.y = textField.frame.maxY + 20
        shareButton.center.x = textField.center.x
        shareButton.frame.origin.y = button.frame.maxY + 20
    }
    
    func configForEdit(item: Item, index: Int) {
        textField.text = item.title
        editingIndex = index
        isEditingMode = true
        currentItem = item
        self.title = "編輯項目"
    }
    
    func configForAdd() {
        editingIndex = nil
        isEditingMode = false
        self.title = "新增項目"
    }
    
    @objc func tapButton() {
        guard let text = textField.text, !text.isEmpty else { return }

        if isEditingMode, let index = editingIndex {
            currentItem.title = text
            delegate?.didEditItem(at: index, item: currentItem)
            CloudSyncMgr.shared.updateToCloud(item: currentItem)
            navigationController?.popViewController(animated: true)
        } else {
            currentItem.title = text
            CloudSyncMgr.shared.saveToCloud(item: currentItem) { [weak self] recordID in
                guard let self else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    currentItem.recordID = recordID
                    delegate?.didAddItem(item: currentItem)
                    navigationController?.popViewController(animated: true)
                }
            }
        }
    }
    
    @objc func tapShareButton() {
        currentItem.isShare.toggle()
        shareButton.configuration?.image = currentItem.isShare ? UIImage(systemName: "square.fill") : UIImage(systemName: "square.dotted")
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}

extension AddViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
