using UnityEngine;

public class ColorChanger : MonoBehaviour
{
    private Renderer rend;
    private static MaterialPropertyBlock propBlock;

    [SerializeField] private Color objectColor = Color.white; // Barva viditelná v Inspectoru

    void Awake()
    {
        rend = GetComponent<Renderer>();

        // Vytvoření MaterialPropertyBlock pouze jednou
        if (propBlock == null)
            propBlock = new MaterialPropertyBlock();

        ApplyColor();
    }

    void ApplyColor()
    {
        rend.GetPropertyBlock(propBlock);
        propBlock.SetColor("_Color", objectColor); // "_Color" musí odpovídat shaderu
        rend.SetPropertyBlock(propBlock);
    }

    void OnValidate() // Spustí se, když změníš barvu v editoru
    {
        if (rend == null) rend = GetComponent<Renderer>();
        ApplyColor();
    }
}
