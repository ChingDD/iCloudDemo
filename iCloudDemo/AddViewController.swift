//
//  AddViewController.swift
//  iCloudDemo
//
//  Created by 林仲景 on 2025/8/11.
//

import UIKit
protocol AddViewControllerDelegate: AnyObject {
    func didAddItem(_ text: String, isSelect: Bool)
    func didEditItem(at index: Int, with text: String, isSelect: Bool)
}

class AddViewController: UIViewController {
    let textField = UITextField()
    let button = UIButton()
    let shareButton = UIButton()
    var isShare: Bool = false
    
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
        shareConfig.image = isShare ? UIImage(systemName: "square.fill") : UIImage(systemName: "square.dotted")
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
    
    func configForEdit(title: String, index: Int, share: Bool) {
        textField.text = title
        editingIndex = index
        isEditingMode = true
        isShare = share
        self.title = "編輯項目"
    }
    
    func configForAdd() {
        textField.text = ""
        editingIndex = nil
        isEditingMode = false
        self.title = "新增項目"
    }
    
    @objc func tapButton() {
        guard let text = textField.text, !text.isEmpty else {
            return
        }
        
        if isEditingMode, let index = editingIndex {
            delegate?.didEditItem(at: index, with: text, isSelect: isShare)
        } else {
            delegate?.didAddItem(text, isSelect: isShare)
        }
        
        navigationController?.popViewController(animated: true)
    }
    
    @objc func tapShareButton() {
        isShare.toggle()
        shareButton.configuration?.image = isShare ? UIImage(systemName: "square.fill") : UIImage(systemName: "square.dotted")
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
